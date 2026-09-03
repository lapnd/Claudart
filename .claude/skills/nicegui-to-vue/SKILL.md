---
name: nicegui-to-vue
description: Decompose a server-side Python UI (NiceGUI, Streamlit, Gradio, Dash) into a framework-free backend plus a Vue SPA — splitting fused callbacks into domain, transport, and view, and making implicit server-held state explicit. Use when porting a NiceGUI/Streamlit app away from Python, or when a migration keeps producing a backend shaped like a UI event loop.
---

# NiceGUI → Go + Vue

NiceGUI is not a UI library sitting on top of an application. It **is** the application: the element tree lives in server-side Python, every callback closes over server state, and the browser is a projection kept in sync over a WebSocket. Streamlit, Gradio, Dash and server-side Blazor have the same shape.

That means the port has no file-to-file mapping. Apply this skill **before** `python-to-go-idioms` — decompose first, translate second. Translating a fused callback produces Go that is shaped like a UI event loop, and no amount of later refactoring recovers from it.

## The one procedure

For **every** callback, binding, and page function in the source, fill three destinations before writing any target code:

| Destination           | What lands there                                           | Where it goes           |
| --------------------- | ---------------------------------------------------------- | ----------------------- |
| **Domain / use case** | the decision, the rule, the calculation, the persistence   | Go, framework-free      |
| **Transport**         | the request/response or event the framework was hiding     | the frozen API contract |
| **View**              | the rendering, the local interaction, the optimistic state | Vue SFC + store         |

A callback that cannot be split into all three has been misread — usually the domain part is one line buried between two UI updates. Write the split into `artifacts/module-inventory.md` per callback; that table, not the Python file layout, is what the ROADMAP tasks are derived from.

```python
# source: one function doing all three
def on_book(self):
    if self.nights.value < 1:                                # domain rule
        ui.notify('at least one night'); return              # view
    booking = Booking(guest=self.guest.value, nights=self.nights.value)
    db.add(booking); db.commit()                             # domain + persistence
    self.table.rows = load_rows(); self.table.update()       # view, via server-held state
    ui.notify(f'booked {booking.id}')                        # view
```

```text
domain    → Bookings.Create(ctx, guest, nights) (Booking, error); nights >= 1 is a domain invariant
transport → POST /bookings {guest, nights} → 201 Booking | 422 {field, message}
view      → BookingForm.vue: submit → store.create() → toast; list refetch or optimistic insert
```

## Mapping table

| NiceGUI                                  | Target                                                                                      |
| ---------------------------------------- | ------------------------------------------------------------------------------------------- |
| `@ui.page('/x')` function                | Vue Router route + view component; the body splits three ways                               |
| `ui.label`, `ui.markdown`                | template interpolation                                                                      |
| `ui.button(on_click=fn)`                 | `@click` handler calling a store action calling the API client                              |
| `ui.input().bind_value(obj, 'field')`    | `v-model` over a `ref`, or a Pinia store field                                              |
| `bind_text_from(obj, 'x', backward=f)`   | `computed()`                                                                                |
| `bind_visibility_from(...)`              | `v-if` / `v-show`                                                                           |
| `@ui.refreshable` + `.refresh()`         | nothing — Vue reactivity is automatic; the `.refresh()` call becomes a store refetch        |
| `ui.table(rows=all_rows)`                | a table component fed by a **paginated, filtered** endpoint                                 |
| `ui.timer(1.0, cb)`                      | `setInterval` + `onUnmounted` for polling; SSE/WebSocket from Go for push                   |
| `ui.notify`                              | a toast component                                                                           |
| `ui.dialog`, `ui.menu`                   | a component with `v-model` open state                                                       |
| `ui.upload`                              | `<input type="file">` + a multipart endpoint                                                |
| `ui.download`                            | a download endpoint, or a signed URL                                                        |
| `app.storage.user`                       | server-side session record + cookie/JWT — **not** `localStorage`                            |
| `app.storage.general`                    | a real datastore in Go; it was shared mutable process state                                 |
| `app.storage.tab` / `app.storage.client` | client-side store, or `sessionStorage`                                                      |
| `app.on_startup` / `on_shutdown`         | wiring and graceful shutdown in `main()`                                                    |
| `run.io_bound` / `run.cpu_bound`         | a goroutine, or a worker pool with a bounded queue                                          |
| background task mutating UI elements     | Go emits an event → SSE/WebSocket → store → components react                                |
| `ui.run(...)`                            | Go HTTP server for the API; Vite dev server, then built assets served or shipped separately |
| `app.get(...)` (native FastAPI routes)   | ordinary Go handlers — these are the only parts that already have a transport               |

## The state inventory is the deliverable that prevents data loss

NiceGUI holds per-user state the source never wrote down: `app.storage.*`, module-level globals, closure captures over a client, and element attributes used as variables (`self.table.rows` above is application state living in a widget). None of this survives the port implicitly.

Enumerate every instance in `artifacts/behavior-contract.md` with four columns: **what it holds**, **whose it is** (one user / one tab / everyone), **how long it lives** (request, session, forever), **where it goes** (client store, server session, database). An entry with no destination is a bug that appears only once two users are online at the same time.

Two traps worth naming:

- **`app.storage.general` looks like a cache and behaves like a database** with no durability and no locking. Decide which one it was; porting it to a Go package-level map reproduces the bug and adds a data race.
- **Server-held widget state is invisible state.** `self.rows`, `element.value`, and anything read back off a NiceGUI element are variables. Grep the source for element attribute reads, not just for `storage`.

## Reachability, security, and the seam

Everything in the source ran server-side, so nothing was ever exposed. In the target, the transport layer is a public API and every endpoint is reachable by anyone.

- A rule enforced by _not rendering a button_ is not enforced. Every such rule becomes a server-side authorization check (`code-quality.md`: deny by default, never trust client-supplied role or tenant).
- A callback that read a database row by an ID held in server state now takes that ID from the client — validate ownership on every one.
- Data the UI never displayed but the callback touched must not be serialized into the response just because it is on the struct.

The contract (OpenAPI) is written **before** handlers exist, and the Vue API client is generated from it. Hand-writing both sides is how the two halves drift.

## Verifying a UI port

The backend gets differential runs against the Python baseline. The UI needs its own evidence, and "it looks right" is not it:

- **Screen inventory with per-screen acceptance**: for each ported screen, the interactions it must support and the observable that proves each one. Derived from the source, not from the new UI.
- **Browser-driven flow tests** on the target for the paths in the smoke test, from Phase 1.
- **Side-by-side run** of the NiceGUI baseline and the new SPA for the highest-risk screens, comparing behavior — not pixels. The frozen POC artifact from `/spec` is the visual reference where the design deliberately changes.
- **Concurrency check**: two sessions in two browsers. Almost every implicit-state defect from the inventory above appears here and nowhere else.

## Anti-patterns

- Recreating NiceGUI's element tree in Go and pushing diffs to a thin Vue shell. That is porting the framework, not the application.
- One endpoint per button, mirroring callbacks one-to-one. Endpoints follow the domain, not the widget layout.
- Moving `app.storage.user` to `localStorage` — it was server-side, cookie-signed, and trusted; `localStorage` is none of those.
- Shipping the whole table to the client because `ui.table(rows=...)` did. The Python version had the list in the same process; the SPA does not.
- Duplicating a domain rule in a Pinia store "so the UI feels fast". Optimistic UI is a rendering decision; the rule stays in Go, and the server's answer wins.
- Starting the Vue side before the API contract is frozen.

## See also

- `.claude/skills/python-to-go-idioms/SKILL.md` — apply after this decomposition, for the Go half.
- `.claude/rules/stack-migration.md` §5 — the binding version of the three-destination split.
- `.claude/rules/code-organization.md` — the hexagonal target both halves must land in.
