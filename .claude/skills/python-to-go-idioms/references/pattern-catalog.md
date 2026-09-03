# Python → Go Pattern Catalog

Worked translations for the rows in `SKILL.md`. Each entry states the Python construct, the Go result, and the decision that is easy to get wrong.

---

## 1. Generators → `iter.Seq` (or a channel)

```python
def batches(items, size):
    for i in range(0, len(items), size):
        yield items[i:i + size]
```

```go
func Batches[T any](items []T, size int) iter.Seq[[]T] {
    return func(yield func([]T) bool) {
        for i := 0; i < len(items); i += size {
            end := min(i+size, len(items))
            if !yield(items[i:end]) {
                return
            }
        }
    }
}
```

Consumed as `for b := range Batches(xs, 100) { ... }`.

**Decision**: `iter.Seq` for pull-style, single-consumer, in-process iteration — the direct analogue of a generator. Use a channel **only** when the producer is genuinely concurrent with the consumer, and then it needs a `context` and a documented close owner. A generator ported to a channel without cancellation leaks a goroutine per call.

Error-producing generators become `iter.Seq2[T, error]`, or a slice plus error when the sequence is small and finite. Do not swallow the error to keep the signature pretty.

---

## 2. Classes and inheritance → interface + embedding

```python
class Notifier(ABC):
    @abstractmethod
    def send(self, msg: Message) -> None: ...

class RetryingNotifier(Notifier):
    def __init__(self, inner: Notifier, attempts: int = 3):
        self.inner, self.attempts = inner, attempts

    def send(self, msg):
        for _ in range(self.attempts):
            try:
                return self.inner.send(msg)
            except TransientError:
                continue
        raise
```

```go
// Declared in the package that CONSUMES it (application/domain), not beside the implementations.
type Notifier interface {
    Send(ctx context.Context, msg Message) error
}

type retryingNotifier struct {
    inner    Notifier
    attempts int
}

func NewRetryingNotifier(inner Notifier, attempts int) Notifier {
    return &retryingNotifier{inner: inner, attempts: attempts}
}

func (r *retryingNotifier) Send(ctx context.Context, msg Message) error {
    var err error
    for i := 0; i < r.attempts; i++ {
        if err = r.inner.Send(ctx, msg); err == nil {
            return nil
        }
        var transient *TransientError
        if !errors.As(err, &transient) {
            return err
        }
    }
    return fmt.Errorf("send after %d attempts: %w", r.attempts, err)
}
```

**Decision**: the Python ABC became a Go interface _for the contract_; the subclass became a struct that holds the thing it wraps _for the behavior_. Embedding (`struct { Base }`) is for genuine shared implementation, not for modelling "is-a". If the Python hierarchy relied on `super()` cooperation or template methods, stop and re-model — reproducing it with embedding produces a design nobody can extend.

---

## 3. Decorators → middleware or functional options

Two different Python decorators translate two different ways.

**Cross-cutting behavior** (`@retry`, `@timed`, `@authenticated`) → middleware.

```python
@timed
@authenticated
def handle(request): ...
```

```go
handler = Timed(Authenticated(handle))     // one chain, composed at the composition root
```

**Configuration** (`@dataclass`-ish decorators, `**kwargs` defaults) → functional options.

```python
client = Client(base_url, timeout=30, retries=3)
```

```go
client := NewClient(baseURL,
    WithTimeout(30*time.Second),
    WithRetries(3),
)

type Option func(*Client)

func WithTimeout(d time.Duration) Option { return func(c *Client) { c.timeout = d } }
```

**Decision**: options are for constructors with several optional knobs. Three required parameters do not need options — take them as parameters. An options struct with thirty pointer fields is `**kwargs` smuggled across the border.

---

## 4. Exceptions → error values

```python
class InsufficientFunds(Exception):
    def __init__(self, balance, requested):
        self.balance, self.requested = balance, requested

def withdraw(account, amount):
    if account.balance < amount:
        raise InsufficientFunds(account.balance, amount)
    ...
```

```go
type InsufficientFundsError struct {
    Balance   Money
    Requested Money
}

func (e *InsufficientFundsError) Error() string {
    return fmt.Sprintf("insufficient funds: balance %s, requested %s", e.Balance, e.Requested)
}

func (a *Account) Withdraw(amount Money) error {
    if a.Balance.LessThan(amount) {
        return &InsufficientFundsError{Balance: a.Balance, Requested: amount}
    }
    ...
}
```

Caller: `var insufficient *InsufficientFundsError; if errors.As(err, &insufficient) { ... }`.

**Decision**: a typed error when the caller needs the data; a sentinel (`var ErrNotFound = errors.New("not found")`, matched with `errors.Is`) when it only needs the identity. Wrap with `%w` at each boundary that adds context, and wrap exactly once per boundary — a message repeated at five layers is five layers logging the same thing.

`finally` → `defer`. `except Exception: pass` → handle it or return it; there is no silent-swallow idiom in Go, and porting one is how a mission loses a failure mode.

---

## 5. `async` → goroutines + `errgroup`

```python
async def enrich_all(ids):
    results = await asyncio.gather(*(fetch(i) for i in ids))
    return results
```

```go
func EnrichAll(ctx context.Context, ids []ID) ([]Record, error) {
    results := make([]Record, len(ids))
    g, ctx := errgroup.WithContext(ctx)
    g.SetLimit(runtime.GOMAXPROCS(0))     // asyncio had no natural bound either; add one deliberately
    for i, id := range ids {
        g.Go(func() error {
            r, err := Fetch(ctx, id)
            if err != nil {
                return fmt.Errorf("fetch %v: %w", id, err)
            }
            results[i] = r
            return nil
        })
    }
    return results, g.Wait()
}
```

**Decision**: writing to distinct indices of a pre-sized slice is race-free; appending to a shared slice is not. `asyncio.gather` cancels nothing by default while `errgroup.WithContext` cancels siblings on first error — if the source relied on all coroutines completing, use `errgroup.Group` without the context, and say so in the translation-rules artifact.

The single biggest port hazard lives here: **Python's event loop made shared mutable state safe by accident.** Every module-level cache, lazy singleton, or memo dict in the source becomes a data race in Go. Port them to a `sync.Map`, a mutex-guarded struct, or — usually better — an injected dependency with explicit lifetime. Run `go test -race` on the ported unit, not once at the end.

---

## 6. `@dataclass` → struct + constructor

```python
@dataclass
class Booking:
    id: str
    guest: str
    nights: int = 1

    def __post_init__(self):
        if self.nights < 1:
            raise ValueError("nights must be >= 1")
```

```go
type Booking struct {
    ID     string
    Guest  string
    Nights int
}

func NewBooking(id, guest string, nights int) (Booking, error) {
    if nights < 1 {
        return Booking{}, fmt.Errorf("nights must be >= 1, got %d", nights)
    }
    return Booking{ID: id, Guest: guest, Nights: nights}, nil
}
```

**Decision**: `__post_init__` validation only holds if nobody can build the struct another way. If the invariant matters, unexport the fields and expose accessors, or keep the type in a package whose API forces `NewBooking`. A constructor that anyone can bypass with `Booking{}` is documentation, not an invariant — decide which one the source actually needed.

`frozen=True` has no direct Go equivalent: unexported fields plus value receivers is the closest, and it is worth it only for real value objects (Money, DateRange).

---

## 7. Comprehensions → loops

```python
active = [u.email for u in users if u.is_active]
```

```go
active := make([]string, 0, len(users))
for _, u := range users {
    if u.IsActive {
        active = append(active, u.Email)
    }
}
```

**Decision**: a loop. Generic `Map`/`Filter` helpers are justified when the same transformation is genuinely reused, not to make Go look like Python. Nested comprehensions almost always hide a step worth naming — the port is the right moment to name it.

---

## 8. `Optional` / `Union` → the shape that carries meaning

| Python                                | Go                                                        | Use when                                       |
| ------------------------------------- | --------------------------------------------------------- | ---------------------------------------------- |
| `Optional[T]` meaning "may be absent" | `(T, bool)`                                               | lookups; absence is normal and not an error    |
| `Optional[T]` meaning "may fail"      | `(T, error)`                                              | the caller needs to know _why_ it is missing   |
| `Optional[T]` on a struct field       | `*T`                                                      | absence must survive serialization round-trips |
| `T = None` default                    | zero value                                                | the zero value is a valid, meaningful default  |
| `Union[A, B]` closed set              | small interface, or a sum-ish struct with a discriminator | A and B are domain alternatives                |
| `Union[A, B]` for overloads           | two functions                                             | almost always                                  |

**Decision**: `*T` everywhere is the lazy port and it spreads nil checks through the domain. Pick per field; write the choice in the translation-rules artifact once so it is not re-litigated per module.

---

## 9. SQLAlchemy → repository port + SQL adapter

```python
class BookingRepo:
    def __init__(self, session): self.session = session
    def get(self, id): return self.session.query(Booking).get(id)
```

```go
// domain (or application) — declares what it needs, imports no driver
type BookingRepository interface {
    Get(ctx context.Context, id BookingID) (Booking, error)
    Save(ctx context.Context, b Booking) error
}

// adapter/postgres — imports the driver, satisfies the interface, owns the row type
type bookingRow struct {
    ID     string `db:"id"`
    Guest  string `db:"guest"`
    Nights int    `db:"nights"`
}

func (r *Repo) Get(ctx context.Context, id domain.BookingID) (domain.Booking, error) {
    var row bookingRow
    if err := r.db.GetContext(ctx, &row, `SELECT ... WHERE id = $1`, string(id)); err != nil {
        if errors.Is(err, sql.ErrNoRows) {
            return domain.Booking{}, domain.ErrBookingNotFound
        }
        return domain.Booking{}, fmt.Errorf("get booking %s: %w", id, err)
    }
    return row.toDomain()
}
```

**Decision**: the ORM model becomes **two** types — a row struct in the adapter and an entity in the domain — with an explicit mapping between them. Collapsing them back into one struct with `db:` tags on the domain entity re-couples the domain to the schema, and it is the single most common way a "hexagonal" port ends up not being one.

Lazy loading has no Go equivalent. Every relationship the Python code traversed implicitly becomes an explicit query or a join, and the N+1 that Python hid becomes visible — enumerate these during the inventory, because they change the endpoint's performance profile and the parity run will show it.

Transactions: pass a `Tx` through the port as an explicit unit-of-work, or keep transaction scope entirely inside one adapter method. Do not leak `*sql.Tx` into the use case.

---

## 10. FastAPI / Flask handler → thin adapter over a use case

```python
@app.post("/bookings")
def create_booking(req: CreateBookingRequest, db=Depends(get_db)):
    booking = Booking(id=uuid4().hex, guest=req.guest, nights=req.nights)
    db.add(booking); db.commit()
    return BookingResponse.from_orm(booking)
```

```go
func (h *Handler) CreateBooking(w http.ResponseWriter, r *http.Request) {
    var req createBookingRequest                    // adapter-owned DTO
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        writeError(w, http.StatusBadRequest, err); return
    }
    booking, err := h.bookings.Create(r.Context(), req.Guest, req.Nights)   // the use case
    if err != nil {
        writeError(w, statusFor(err), err); return
    }
    writeJSON(w, http.StatusCreated, bookingResponseFrom(booking))
}
```

**Decision**: the handler decodes, calls one use case, and encodes. Any business rule visible in a handler is a rule the port put in the wrong layer. `Depends()` becomes constructor injection at the composition root — not a global container, and not a package-level `var db *sql.DB`.

pydantic validation splits: **transport-shape validation** (required field, parseable int) stays in the adapter DTO; **business validation** (nights ≥ 1, guest must exist) moves into the domain constructor or use case. Porting all of pydantic into the handler leaves a domain that trusts its inputs.

---

## 11. Configuration and logging

```python
TIMEOUT = int(os.environ.get("TIMEOUT", "30"))        # at import time, in three modules
log = logging.getLogger(__name__)
```

```go
type Config struct {
    Timeout time.Duration
    DSN     string
    Addr    string
}

func Load() (Config, error) { /* parse env once, validate, return */ }

func main() {
    cfg, err := Load()
    logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
    repo := postgres.New(db, logger)
    ...
}
```

**Decision**: one typed config resolved once at `main()`, then injected. Environment reads scattered through packages are the port-time habit that makes the target untestable and undeployable to a second environment; the source's scattered `os.environ` calls are exactly what the inventory should flag.

Loggers are injected, never package-level. Structured fields replace f-string messages; nothing sensitive is logged (`code-quality.md`).

---

## 12. Tests

`pytest` fixtures → explicit constructors and table-driven tests. A fixture that builds a whole app becomes an in-memory fake satisfying the port interface — which is the payoff for having declared the interface at the consumer in the first place.

```go
func TestWithdraw(t *testing.T) {
    tests := []struct {
        name    string
        balance Money
        amount  Money
        wantErr error
    }{
        {"sufficient", money(100), money(40), nil},
        {"exact", money(40), money(40), nil},
        {"insufficient", money(10), money(40), &InsufficientFundsError{}},
    }
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) { ... })
    }
}
```

During a port, the test's job is parity: it encodes what the **Python** did, and it is written before the Go exists so it can be seen failing (`evidence-gauntlet.md`). A test written after the Go code, from the Go code, proves the Go code agrees with itself.
