<!-- AI agents: this is a human-oriented manual. The binding contract is .claude/rules/stack-migration.md — read that, not this file, when acting. Read this file only when the user asks how to run a migration. -->

# Hướng dẫn `/migrate` — port một codebase sang stack khác

Tài liệu này hướng dẫn chạy một mission port từ đầu đến cutover. Ví dụ xuyên suốt là **NiceGUI (Python) → Go backend + Vue SPA, hexagonal, modular** — nhưng quy trình giống hệt cho Django→Nest, Streamlit→React, Python worker→Go.

- [README](../README_VI.md) là phần giới thiệu · [GUIDE](GUIDE.md) là sổ tay tổng hợp mọi command
- Hợp đồng ràng buộc agent nằm ở `.claude/rules/stack-migration.md`; file này chỉ giải thích cho người dùng

## Mục lục

- [Khi nào dùng `/migrate`](#khi-nào-dùng-migrate)
- [Toàn cảnh: bạn sẽ bỏ ra bao nhiêu công](#toàn-cảnh-bạn-sẽ-bỏ-ra-bao-nhiêu-công)
- [Bước 0 — Chuẩn bị trước khi gõ lệnh](#bước-0--chuẩn-bị-trước-khi-gõ-lệnh)
- [Bước 1 — Phiên planning (`/migrate`)](#bước-1--phiên-planning-migrate)
- [Nguyên tắc nền: dịch hành vi, không dịch cấu trúc](#nguyên-tắc-nền-dịch-hành-vi-không-dịch-cấu-trúc)
- [Bước 2 — Review trước khi nói "go"](#bước-2--review-trước-khi-nói-go)
- [Bước 3 — Các phiên thực thi (`/spec-run`)](#bước-3--các-phiên-thực-thi-spec-run)
- [Ngân sách model và token](#ngân-sách-model-và-token)
- [Bước 4 — Cutover và đóng mission](#bước-4--cutover-và-đóng-mission)
- [Hai skill tham chiếu](#hai-skill-tham-chiếu)
- [Ví dụ đầy đủ: eDT Installer (Cloudfabric `cf`) → Go + Vue](#ví-dụ-đầy-đủ-edt-installer-cloudfabric-cf--go--vue)
- [Triệu chứng → nguyên nhân → cách sửa](#triệu-chứng--nguyên-nhân--cách-sửa)
- [Câu hỏi thường gặp](#câu-hỏi-thường-gặp)

## Khi nào dùng `/migrate`

| Tình huống                                                        | Dùng            |
| ----------------------------------------------------------------- | --------------- |
| Đổi ngôn ngữ, runtime, hoặc UI framework; hành vi phải giữ nguyên | `/migrate`      |
| Tái cấu trúc trong cùng một ngôn ngữ và một build                 | `/refactor`     |
| Một module lẻ, không vượt ranh giới framework nào                 | `/plan` + skill |
| Viết lại và **được phép** đổi hành vi/sản phẩm                    | `/spec`         |

Ranh giới quyết định: `/refactor` chứng minh tương đương bằng cách diff trong **một** build. Port có **hai** build — không có phép diff nào chạy được — nên parity phải chứng minh bằng cách dựng cả hai stack lên và so output. Đó là toàn bộ lý do `/migrate` tồn tại.

## Toàn cảnh: bạn sẽ bỏ ra bao nhiêu công

```
PHIÊN 1 (đắt, model mạnh)          ← bạn ngồi cùng, trả lời phỏng vấn
  /migrate ...
    ├─ phỏng vấn 3 quyết định
    ├─ ghim baseline + behavior contract
    ├─ translation-rules.md   ← artifact quan trọng nhất
    ├─ module-inventory.md
    ├─ api-contract/ (OpenAPI)  ← đóng băng TRƯỚC khi có code target
    └─ SPEC.md + ROADMAP.md   → bạn duyệt MỘT lần

PHIÊN 2..N (rẻ, tự động)           ← bạn chỉ xem báo cáo cuối mỗi phase
  /spec-run <slug>
    lặp: 1 translation unit → test đỏ trước → implement → differential run → tick
    rotate ở mỗi phase boundary (mở session mới, /start, /spec-run lại)

PHIÊN CUỐI                          ← bạn xác nhận demo
  awaiting-final-review → bạn nói "approved" → done
```

Công của bạn dồn hết vào phiên 1 và các mốc xác nhận. Phần dịch code chạy tự động và resume được sau mọi gián đoạn — trạng thái nằm trong `.claude/specs/`, không nằm trong session.

## Bước 0 — Chuẩn bị trước khi gõ lệnh

Năm việc này làm trước sẽ tiết kiệm nhiều giờ về sau:

1. **Repo nguồn sạch và commit hết.** Baseline được ghim bằng SHA; một working tree bẩn khiến mọi trích dẫn contract lệch.
2. **Biết cách chạy app nguồn bằng một lệnh.** Parity là chạy song song hai stack; nếu bản Python phải dựng thủ công 10 bước thì mỗi lần verify đều đau.
3. **Có dữ liệu thật (hoặc bản sao có hình dạng thật).** Data-migration rehearsal diễn ra ở phase đầu tiên chạm persistence, không phải phase cuối.
4. **Biết mình muốn bỏ cái gì.** Tính năng nào không port — nói ngay ở phỏng vấn để nó vào `Must-NOT-Have`. Đây là hàng rào ngăn executor tự ý làm thêm.
5. **Quyết định repo đích.** Cùng repo hay repo mới? Nếu repo mới, `/migrate` sẽ ghi thêm `target-repo:` vào SPEC.

Không cần chuẩn bị: bảng dịch idiom, cấu trúc package Go, danh sách endpoint — đó chính là việc của phiên 1.

## Bước 1 — Phiên planning (`/migrate`)

```
you>  /start
you>  /migrate port app NiceGUI trong python/src sang Go backend + Vue SPA, hexagonal, modular
```

Agent đọc `.claude/rules/stack-migration.md`, tạo `.claude/specs/YYYY-MM-DD-<slug>/`, và bắt đầu phỏng vấn. **Khi spec đang `drafting`, agent không được viết một dòng code implementation nào** — đây là khoá cứng, không phải phép lịch sự.

### Ba câu hỏi mà source code không trả lời được

Agent sẽ hỏi ba thứ này; chuẩn bị sẵn câu trả lời:

**1. Hình dạng target.** Một service hay tách backend + SPA? Framework nào? Seam nằm ở đâu — REST/OpenAPI, gRPC, hay event? Trả lời cụ thể; "Go và Vue" là chưa đủ để đóng băng contract.

**2. Hình dạng cutover.** Chọn một:

| Kiểu              | Nghĩa là                                             | Hợp khi                                  |
| ----------------- | ---------------------------------------------------- | ---------------------------------------- |
| **Big-bang**      | Đổi một lần, tắt bản cũ                              | Nội bộ, ít user, rollback rẻ             |
| **Strangler-fig** | Reverse proxy route từng phần sang target            | Đang chạy production, muốn giảm rủi ro   |
| **Parallel-run**  | Hai stack cùng nhận request, diff response, chưa cắt | Rủi ro cao, cần bằng chứng trước khi cắt |

Hỏi ở đây chứ không hỏi ở cổng cuối — phát hiện muộn sẽ mở lại roadmap.

**3. Phạm vi của nguồn.** Cái gì port, cái gì bỏ, cái gì ở lại Python vĩnh viễn.

### Những artifact phiên 1 sinh ra

Trong `.claude/specs/YYYY-MM-DD-<slug>/artifacts/`:

| File                   | Là gì                                                                                  | Vì sao quan trọng                                                       |
| ---------------------- | -------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| `behavior-contract.md` | Mọi hành vi quan sát được, đánh ID `B1`/`V1`, trích dẫn `file:line` baseline           | Chuẩn để so; viết từ code **trước** khi đổi, không phải từ code đã port |
| `translation-rules.md` | Bảng idiom **của chính dự án này**: pattern nguồn → pattern đích → vì sao → ví dụ thật | Thứ giữ cho phiên số 9 dịch một decorator giống hệt phiên số 2          |
| `module-inventory.md`  | Từng file nguồn → package/component đích, thứ tự phụ thuộc, nhãn rủi ro                | Đầu vào để sinh ROADMAP — **không** phải checklist thứ hai              |
| `api-contract/`        | OpenAPI (hoặc proto) đóng băng                                                         | Không có nó, public API trở thành tai nạn của thứ tự sinh code          |

Ngoài ra agent chạy **phantom-feature sweep**: mọi comment deprecated, type hint mồ côi, tham chiếu schema chết trong nguồn phải được phân loại — hoặc xoá khỏi nguồn (rồi ghim lại baseline), hoặc ghi vào `Must-NOT-Have`. Bỏ qua bước này là cách agent hồi sinh một tính năng đã bị gỡ từ hai năm trước.

### Về `translation-rules.md`

Đây là artifact đáng đọc kỹ nhất. Nó được seed từ hai skill tham chiếu, nhưng **mọi dòng phải được thay bằng ví dụ thật từ code của bạn**. Một dòng chung chung không neo vào source nào sẽ được mỗi phiên hiểu một kiểu.

```markdown
| Nguồn                           | Đích                                        | Vì sao                                      | Ví dụ                                               |
| ------------------------------- | ------------------------------------------- | ------------------------------------------- | --------------------------------------------------- |
| `@dataclass` có `__post_init__` | struct + `NewX() (X, error)`, field private | invariant phải không bypass được            | `app/booking.py:12` → `internal/booking/booking.go` |
| `app.storage.user['cart']`      | session record server-side + cookie ký      | vốn là state phía server, không phải client | `app/cart.py:8` → `internal/session`                |
```

## Nguyên tắc nền: dịch hành vi, không dịch cấu trúc

Đây là điều dễ làm sai nhất và tốn kém nhất khi sửa muộn.

**Hợp đồng 1-1 là hành vi quan sát được — không phải cấu trúc code.** Behavior contract phải sống nguyên vẹn. Phần implementation bên dưới thì không: chỗ nào Go có kiểu dữ liệu tốt hơn, mô hình concurrency tốt hơn, primitive chuẩn hơn, hay thư viện đã giải quyết sẵn — **phải dùng cái đó**. Một bản dịch trung thành từng dòng là một khuyết tật đội lốt sự trung thành.

Chính parity gate là thứ cho phép tự do này: differential run đã ghim hành vi, nên mọi thứ bên dưới là của bạn để thiết kế lại.

Bốn dấu hiệu nên viết lại thay vì dịch:

| Trong Python                                                                               | Trong Go nên là                                                                |
| ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------ |
| Tiện ích tự viết vì Python thiếu (ring buffer + lock, retry/backoff, dispatch bằng `dict`) | Thường **xoá** được — `chan`, `context`, `sync`, generics đã có sẵn            |
| Cấu trúc sinh ra vì GIL (thread pool để lách blocking I/O, queue giả lập concurrency)      | goroutine + `errgroup`; nhỏ hơn và nhanh hơn, không chỉ khác                   |
| Hình dạng động Python trả nổi còn Go thì không (`dict[str, Any]`, `getattr` dispatch)      | Đặt type thật. Mang `map[string]any` sang là mang cả cái schema còn thiếu sang |
| API kiểu **pull** chỉ vì framework chỉ cho phép poll                                       | Go **push** được — SSE/WebSocket. Đừng port vòng poll mà target không cần      |

Code bị xoá là bản dịch tốt nhất có thể.

Hàng rào vẫn là `ai-behavior.md` §2/§4: chọn dạng Go tốt hơn **cho đúng hành vi đang port**, không phát minh năng lực mà nguồn chưa từng có. "Go làm theo cách này" là lý do; "biết đâu sau này cần" thì không.

### Thư viện: chỉ permissive, tuyệt đối không GPL/AGPL

Port là lúc codebase nạp phần lớn dependency mới, nên kỷ luật license rẻ nhất ở đây và đắt nhất về sau.

- **Không GPL, không AGPL** trong dependency graph của code phát hành. AGPL mở rộng copyleft sang cả việc phục vụ qua mạng — với sản phẩm SaaS đó là khác biệt giữa "ship được" và "phải public source". Chỉ dùng MIT, BSD-2/3, Apache-2.0, ISC. MPL-2.0 là copyleft mức file, thường chấp nhận được, nhưng phải ghi lại như một quyết định.
- **Link khác với deploy.** Ràng buộc này áp cho thứ binary/bundle link hoặc dẫn xuất. Chạy một chương trình copyleft **nguyên bản** như một service/container riêng là tình huống khác — nếu mission có làm vậy, ghi rõ vào `NOTES.md` thay vì để rule âm thầm cho phép hoặc âm thầm cấm.
- **Kiểm license tại đúng version đã pin, không kiểm theo trí nhớ.** Nhiều project lớn đã đổi license; một bài blog hai năm trước không phải bằng chứng.
- **Ưu tiên stdlib → module permissive nhỏ → framework.** `net/http`, `encoding/json`, `database/sql`, `log/slog`, `context`, `sync` phủ phần lớn nhu cầu; nhiều dependency Python đơn giản là không cần đối ứng bên Go.
- **Ép bằng lệnh, không bằng lời.** Một license scan trên dependency graph đã resolve, exit nonzero khi gặp license bị cấm, chạy trong phase validation. Danh sách trong tài liệu không phải là gate.

Điểm khởi đầu permissive đáng tin (MIT / BSD / Apache-2.0 — **vẫn phải verify tại version bạn pin**): `chi` hoặc mux của `net/http`; `pgx`/`sqlx` + `sqlc`; `golang-migrate` hoặc `goose`; `log/slog`; `koanf` hoặc `envconfig`; `golang.org/x/sync/errgroup`; `testify`; `oapi-codegen` hoặc `ogen`; `google/uuid`; `shopspring/decimal`. Phía Vue: Vue, Vue Router, Pinia, Vite và các component library chính đều MIT.

## Bước 2 — Review trước khi nói "go"

Agent dừng ở `poc-review` và báo cáo. Trước khi duyệt, đọc bốn thứ:

- [ ] **`SPEC.md` → Must-NOT-Have.** Đây là hàng rào. Thiếu ở đây nghĩa là executor sẽ tự ý làm thêm.
- [ ] **`SPEC.md` → Acceptance Scenarios.** Mỗi cái phải là _hành động cụ thể → quan sát nhị phân_. "UI hoạt động" là scenario hỏng; "POST /bookings với fixture 3 → 201 và body khớp baseline" là scenario tốt.
- [ ] **`artifacts/translation-rules.md`.** Có dòng nào còn ví dụ generic không? Sửa ngay bây giờ rẻ hơn sửa ở phase 4.
- [ ] **Dependency mới.** Có cái nào GPL/AGPL không? Bắt phải có một license gate chạy trong phase validation, không phải một dòng hứa trong tài liệu.
- [ ] **Tier annotation.** Mỗi task có `(tier: …)` chưa, và `executor-tier:` có phải tier rẻ nhất phủ được roadmap không?
- [ ] **`ROADMAP.md` phase 1.** Phase 1 phải kết thúc bằng một **smoke path chạy được xuyên hệ thống**. Nếu phase 1 chỉ toàn "dựng scaffold", yêu cầu sửa: một port mà lần chạy end-to-end đầu tiên nằm ở phase cuối là một port không có bằng chứng sớm.

Duyệt bằng "go" / "ok làm đi". **Đó là standing approval** — từ đó `/spec-run` chạy hết roadmap mà không hỏi lại, cho tới cổng cuối.

Nếu muốn có checkpoint git trong lúc chạy, nói **trước khi** duyệt: "per-task" hoặc "per-phase". Mặc định là `commits: user` — agent không tự commit.

## Bước 3 — Các phiên thực thi (`/spec-run`)

Mở session **mới** (đây là thiết kế, không phải khuyến nghị):

```
you>  /start
you>  /spec-run <slug>
```

Mỗi vòng lặp: chọn một translation unit → viết test dẫn xuất từ hành vi Python và **xem nó đỏ trước** → implement → chạy `verify:` → tick + ghi evidence vào LEDGER.

### Ba loại bằng chứng bạn sẽ thấy trong LEDGER

- **Differential run** — dựng cả hai stack, cùng input, diff response. Đây là bằng chứng parity duy nhất được tính.
- **Contract diff** — OpenAPI sinh từ target so với contract trích từ baseline. Rẻ nhất, chạy ở mọi phase boundary chạm seam.
- **Architecture gate** — một lệnh có exit code, ví dụ danh sách dependency bắc cầu của package domain không được chứa `net/http`, `database/sql`, hay package UI nào. Tên thư mục không chứng minh gì cả.

### Rotate ở phase boundary

Cuối mỗi phase agent hỏi _"checkpoint và rotate, hay chạy tiếp?"_. **Nên rotate.** Port là mission dài; một session mới đọc lại file thắng một session đã compact đang cố nhớ. Rotate = `/checkpoint`, đóng terminal, mở session mới, `/start`, `/spec-run <slug>`.

Bạn cũng có thể tắt terminal bất cứ lúc nào. Session sau khôi phục từ file, kể cả khi đang dở một task.

### Khi spec bị `blocked`

Chạy **cùng một lệnh** từ một session mạnh hơn:

```
you>  /spec-run <slug>          # từ session model mạnh hơn
```

Escalate không phải một workflow khác. Session mạnh đọc diagnosis, tìm hướng khác, gỡ block, rồi đề nghị rotate xuống lại cho phần việc thường.

### Việc bạn nên tự làm giữa các phase

- Mở app target thật và bấm thử vài luồng. Test xanh không chứng minh app chạy.
- **Mở hai browser session cùng lúc.** Gần như mọi lỗi từ state ẩn phía server chỉ lộ ra ở đây.
- Đọc `NOTES.md → Current Acceptance Delta`. Nếu nó không đổi qua nhiều phase, tiến độ đang giả.

## Ngân sách model và token

Port là loại mission dài nhất CLAUDART chạy, nên kỷ luật tier không phải chuyện tinh tế — nó quyết định mission về đích hay cháy ngân sách ở phase 2. Roadmap phải mang sẵn annotation `(tier: …)` để phiên thực thi khỏi tự suy luận lại.

| Tier         | Việc của một port nằm ở đây                                                                                                                                                |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **fast**     | Unit cơ học có `verify:` nhị phân — value object thành struct, comprehension thành loop, mapping DTO, sinh lại client từ contract, chạy sweep, chạy gate kiến trúc/license |
| **standard** | Phần lớn khối lượng: port một use case kèm test, một feature module SPA, một adapter                                                                                       |
| **strong**   | Decompose callback fused, mọi thứ chạm concurrency hoặc shared state, thiết kế seam, schema và data migration, biên auth, và mọi lần gỡ block                              |

Năm đòn bẩy thực sự tiết kiệm:

1. **Artifact chính là tối ưu token.** `behavior-contract.md`, `translation-rules.md`, `module-inventory.md` tồn tại để phần suy luận đắt xảy ra **một lần** ở phiên planning; mọi phiên sau đọc một quyết định thay vì suy lại. Mission mà các phiên rẻ cứ phải đọc lại toàn bộ source là mission hỏng artifact, không phải hỏng model.
2. **Đọc unit, đừng đọc module.** Inventory chỉ đích danh vùng source mà task cần. Nạp một file UI 4.000 dòng để port một callback là khoản lãng phí lớn nhất của một port.
3. **Verify cao hơn execute một tier ở bề mặt rủi ro.** Chạy rẻ + kiểm mạnh là bất đối xứng tối ưu chi phí, và đúng chỗ mà defect đắt của port trú ngụ (concurrency, quyền sở hữu state, auth).
4. **Output cồng kềnh ghi ra file, tham chiếu bằng path.** Differential run, contract diff, license scan không bao giờ được paste vào LEDGER hay vào session.
5. **Rotate ở phase boundary thay vì cố kéo một session đang xuống sức.** Một phiên mới đọc lại bốn file rẻ hơn một phiên đã compact đang cố dựng lại chúng — và ít sai hơn.

Escalate bằng cách rotate, không bằng cách cày: hai lần thất bại trên cùng một unit là tín hiệu; lần thứ ba ở cùng tier đắt hơn là mở thẳng session mạnh. Và khi một tier tỏ ra sai — task `fast` phải escalate, hoặc task `strong` hoá ra cơ học — ghi vào `NOTES.md` để phần roadmap còn lại được gán tier lại, thay vì lặp lại phán đoán sai đó thêm ba mươi unit nữa.

## Bước 4 — Cutover và đóng mission

Cổng cuối chạy xong, spec chuyển `awaiting-final-review` và **dừng**. Agent không tự đóng mission.

Definition of Done của một port có thêm ba điều so với `/refactor`:

- [ ] Cutover đã thực hiện, hoặc đã lên lịch kèm điều kiện kích hoạt
- [ ] Repo nguồn đã được đánh dấu (archive, freeze, hoặc thu hẹp còn phần chưa port)
- [ ] Có đường rollback được ghi rõ

Một target không ai chuyển sang dùng là mission chưa xong, không phải mission hoàn thành. Khi bạn xác nhận, agent flip `done`, ghi JOURNAL, và chuyển folder sang `.claude/specs/done/`.

## Hai skill tham chiếu

Nạp theo nhu cầu, không auto-load. Agent tự gọi khi gặp construct tương ứng; bạn cũng có thể gọi tay.

| Skill                 | Dùng khi                                                                                               |
| --------------------- | ------------------------------------------------------------------------------------------------------ |
| `nicegui-to-vue`      | **Trước tiên.** Tách callback NiceGUI thành domain / transport / view, và liệt kê state ẩn phía server |
| `python-to-go-idioms` | **Sau đó.** Dịch từng construct Python sang Go idiomatic, đặt đúng tầng hexagonal                      |

Thứ tự quan trọng. Dịch một callback đã fuse UI+state+domain sẽ ra một chương trình Go có hình dạng của một event loop, và không refactor nào cứu được về sau.

## Ví dụ đầy đủ: eDT Installer (Cloudfabric `cf`) → Go + Vue

Ví dụ này lấy từ một codebase thật: **Cloudfabric Installer** (`~/workspace/byoc/src`, package `cf`, v0.1.93) — công cụ deploy nền tảng eDT lên AWS/Azure/on-prem, viết bằng Python với UI NiceGUI. Số liệu bên dưới đọc trực tiếp từ repo, không phải ví dụ dựng.

### Khảo sát: nó không "fused" như một app NiceGUI điển hình

Đây là phát hiện quan trọng nhất và nó thay đổi toàn bộ hình dạng mission:

```
~93.000 dòng Python (kể cả test)

CHỈ 7 file import nicegui — tất cả trong cf/web/:
  ui.py (4.679)  panels.py (3.403)  app.py  theme.py
  maintenance_ui.py  costguide.py  guide_content.py

KHÔNG import nicegui — tức là đã sẵn sàng để port:
  cf/engine.py        cf/declarative.py (5.200)   cf/state.py
  cf/steps/           cf/providers/{aws,azure,onprem,local}/
  cf/teardown.py      cf/upgrade/                 cf/labtemplates.py
  cf/compliance/      cf/dns/                     cf/cli.py
  cf/web/jobs.py (1.858)  ← docstring ghi rõ: "Nothing here imports NiceGUI"
```

Domain **đã** tách sẵn: `cf/web/jobs.py` chạy đúng `cf.engine.Engine` mà CLI chạy, trong background thread. Vậy phần thật sự fused chỉ là `ui.py` + `panels.py` — khoảng 8.100 dòng — chứ không phải cả codebase.

Hệ quả cho SPEC: phần lớn `cf/` là **dịch idiom** (`python-to-go-idioms`), chỉ `cf/web/ui.py` và `cf/web/panels.py` cần **decompose** (`nicegui-to-vue`). Đừng gán cả mission vào một chiến lược.

### Seam đã tồn tại sẵn — chỉ là nó đang cải trang

`cf/web/jobs.py` giữ event trong một ring có khoá:

```python
_events: deque = field(default_factory=lambda: deque(maxlen=RING_SIZE))   # RING_SIZE = 20_000
_seq: int = 0
_lock: threading.Lock = ...

def events_since(self, cursor: int) -> tuple[list[dict], int]:
    """Return events newer than ``cursor`` and the new cursor (latest seq)."""
    with self._lock:
        fresh = [e for e in self._events if e["seq"] > cursor]
        return fresh, self._seq
```

`events_since(cursor)` **chính là một API contract** đã viết sẵn bằng Python. Nó map thẳng sang seam của target:

```yaml
POST   /api/jobs                      → {id}                    # jobs.start
GET    /api/jobs/{id}                 → snapshot()              # status + step_status + outputs
GET    /api/jobs/{id}/events?since=N  → {events[], cursor}      # events_since — polling fallback
GET    /api/jobs/{id}/stream          → text/event-stream       # đường chính, có replay từ since
POST   /api/jobs/{id}/cancel          → 202                     # request_cancel()
```

Bài học tổng quát: **trước khi thiết kế seam từ đầu, tìm xem nguồn đã có sẵn một seam chưa.** Một module cố tình không import UI framework thường đã là contract của bạn, chỉ thiếu lớp HTTP.

### Ba đích cho một callback thật

Nút Deploy trong `panels.py`:

```
domain     → cf.engine.Engine.Run(ctx, project, env, action, opts) — đã framework-free,
             port sang internal/engine bằng python-to-go-idioms
transport  → POST /api/jobs  +  GET /api/jobs/{id}/stream   (bảng trên)
view       → DeployPanel.vue + useJobStream(jobId) trong Pinia store;
             progress/log/topology là ba component đọc cùng một stream
```

### "Đừng dịch 1-1" trông như thế nào ở đây

Bốn ví dụ lấy từ chính code này — đây là những dòng đáng viết vào `translation-rules.md`:

| `cf` (Python)                                                       | Go **không nên** làm gì                        | Go **nên** làm gì                                                                                                                    |
| ------------------------------------------------------------------- | ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `deque(maxlen=20_000)` + `threading.Lock` + client poll `ui.timer`  | Port y nguyên ring + lock, rồi client vẫn poll | Job phát event vào channel; handler stream SSE. Giữ ring **chỉ** để late-joiner replay từ `since`. Vòng poll 0,1s biến mất hoàn toàn |
| `threading.Thread` + `threading.Event` cho `request_cancel()`       | `sync.WaitGroup` + một `bool` có mutex         | `context.WithCancel`; `request_cancel()` trở thành `cancel()`, và mọi bước con hủy theo miễn phí                                     |
| event là `dict`: `{kind, step_id, title, detail, attempt, seq, ts}` | `map[string]any`                               | struct có type + `EventKind` là enum; `kind` sai chính tả trở thành lỗi compile thay vì log câm                                      |
| `_MANAGER` / `_UPTIME_KUMA_MANAGER` singleton toàn process          | biến package-level trong Go (giờ là data race) | một `PortForwardManager` inject từ composition root, key theo user/session                                                           |

Ba trong bốn dòng này khiến code Go **ít hơn** code Python, không phải nhiều hơn. Đó là dấu hiệu bản dịch đúng.

### `ui.timer` không phải một pattern — nó là ba

Trong `cf/web` có 33 lời gọi `ui.timer` (20 ở `panels.py`, 13 ở `ui.py`) làm ba việc khác hẳn nhau. Dịch chung một kiểu là sai cả ba:

| Cách dùng                                                    | Ví dụ trong repo                          | Đích bên Vue/Go                                          |
| ------------------------------------------------------------ | ----------------------------------------- | -------------------------------------------------------- |
| Poll event của job                                           | vòng poll chính trong `ui.py`             | **Biến mất** — SSE đẩy từ Go                             |
| Debounce ô nhập liệu                                         | `_dash_search_deb` 0,35s; `_dbounce` 0,4s | `watchDebounced` phía client; không có gì chạy ở server  |
| Bơm terminal web                                             | `_pump` 0,1s + `_check_target` 0,5s       | WebSocket hai chiều tới một PTY adapter bên Go           |
| Refresh panel sau một hành động (`ui.timer(..., once=True)`) | rải khắp `panels.py`                      | **Biến mất** — reactivity của Vue lo, hoặc store refetch |

### Nợ ẩn phải kê tên trước khi port

- `observability.py` ghi thẳng trong comment: _"Process-wide singleton so the forward survives page reloads (single-user tool)."_ Giả định **single-user** đó vỡ ngay khi lên SPA nhiều người dùng. Nó phải vào behavior contract kèm đích rõ ràng, không được để implicit.
- Multi-user mới làm dở: đã có `workspace_subpath`, owner key của `JobManager`, `Runner.base_env` (xem `tests/test_web_multiuser.py`). Port là lúc hoàn tất, không phải lúc sao chép trạng thái nửa vời.
- Codebase **không** dùng `app.storage.*` — nên state ẩn nằm ở singleton cấp module và closure, chứ không ở nơi thường tìm. Grep `^[A-Z_]+ = ` và `global ` chứ đừng chỉ grep `storage`.
- Nguồn sự thật khả biến duy nhất là **file JSON state của engine**. Nó quyết định thứ tự phase: data-migration rehearsal phải nằm ở phase đầu tiên chạm state, không phải phase cuối.

### Phase và tier gợi ý

| Phase | Nội dung                                                                 | Tier chủ đạo                              |
| ----- | ------------------------------------------------------------------------ | ----------------------------------------- |
| 1     | Đóng băng seam jobs (OpenAPI) + handler + SSE + **smoke path chạy được** | `strong` cho seam, `standard` cho handler |
| 2     | `engine` / `state` / `steps` → `internal/`; provider sau lưng port       | `standard`, `strong` cho concurrency      |
| 3     | Feature module SPA: deploy, status, log, topology                        | `standard`                                |
| 4     | Observability, terminal, multi-user — nơi `_MANAGER` phát nổ             | `strong`                                  |
| 5     | Cutover strangler-fig: proxy route từng màn hình sang target             | `standard`                                |

Phase 1 kết thúc bằng một lần deploy thật chạy xuyên từ SPA tới engine — không phải scaffold. Từ đó trở đi mọi phase đều có differential run để so.

### Lệnh khởi động

```
you>  /start
you>  /migrate port eDT Installer (~/workspace/byoc/src, package cf) sang Go backend + Vue SPA.
      cf/web/ui.py và panels.py là phần fused cần decompose; phần cf/ còn lại đã framework-free.
      Hexagonal, modular. Seam là REST + SSE quanh jobs. Thư viện chỉ permissive, không GPL/AGPL.
```

Ba câu trả lời cần chuẩn bị cho phỏng vấn: **target** = Go API + Vue SPA, seam REST/OpenAPI + SSE; **cutover** = strangler-fig (đang có người dùng); **scope** = `cf/cli.py` ở lại hay port sau, `costguide`/`guide_content` có port không.

## Triệu chứng → nguyên nhân → cách sửa

| Triệu chứng                                               | Nguyên nhân thật                                                                         | Sửa                                                                                                 |
| --------------------------------------------------------- | ---------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| Go đọc như Python có dấu ngoặc nhọn                       | Transliterate thay vì translate                                                          | Neo `translation-rules.md` vào ví dụ thật; đọc `python-to-go-idioms`                                |
| Backend Go có hình dạng một event loop UI                 | Bỏ qua bước decompose                                                                    | Dừng lại, chạy `nicegui-to-vue` trên các callback đã port                                           |
| Test xanh nhưng app trả kết quả sai                       | Không có differential run, chỉ có unit test                                              | Yêu cầu smoke path + differential run làm phase validation                                          |
| Agent dựng lại một tính năng đã bị gỡ                     | Phantom reference trong nguồn                                                            | Chạy lại phantom sweep; phân loại vào Must-NOT-Have hoặc xoá ở nguồn                                |
| Hai user cùng lúc thì dữ liệu lẫn nhau                    | `app.storage.*` / global chưa được liệt kê và cấp đích                                   | Bổ sung state inventory vào behavior contract, mở lại task liên quan                                |
| Mọi thứ nằm dưới `internal/`, không có public API rõ ràng | Seam chưa đóng băng trước khi sinh code                                                  | Viết `api-contract/` trước, sinh client từ nó                                                       |
| Task lặp lại mà delta không đổi                           | Retry không khác về bản chất                                                             | Escalate: `/spec-run` từ session mạnh hơn                                                           |
| Go dài hơn Python mà làm đúng một việc                    | Dịch cấu trúc thay vì hành vi — ring+lock, thread pool, dispatch dict được port y nguyên | Xem lại `translation-rules.md`; hỏi "Go có sẵn cái này chưa?" trước khi port                        |
| Phát hiện một dependency GPL/AGPL đã ăn sâu               | Không có license gate ở phase validation                                                 | Thêm license scan exit-nonzero ngay; thay thư viện khi nó còn ở một chỗ                             |
| Token cháy nhanh mà tiến độ chậm                          | Chạy mọi unit ở tier mạnh, hoặc nạp cả module để port một hàm                            | Gán lại tier theo §10; đọc unit theo `module-inventory.md`, không đọc cả file                       |
| Phát hiện lỗi có sẵn trong bản Python                     | —                                                                                        | Ghi vào `NOTES.md` làm finding; **không** sửa lén — nó đổi hành vi và parity diff sẽ báo regression |

## Câu hỏi thường gặp

**Có nên dựng một `MIGRATION.md` với checklist file-by-file không?**
Không. `ROADMAP.md` đã là danh sách task duy nhất, `LEDGER.md` đã là log. Một checklist song song sẽ lệch pha và bạn sẽ không biết cái nào đúng. `module-inventory.md` là đầu vào để sinh roadmap, không phải nơi tick.

**Chạy `/spec-run` trên model rẻ được không?**
Được — đó là thiết kế. `SPEC.md` ghi `executor-tier:` là tier rẻ nhất chạy nổi roadmap. Gặp task khó thì escalate bằng cùng lệnh từ session mạnh hơn.

**Mission mất bao lâu?**
Tính bằng số phase và số translation unit, không tính bằng giờ. Cỡ đúng của một unit là một module nguồn hoặc một hành vi mạch lạc — vừa một vòng lặp của một context window.

**Có thể port từng phần rồi dừng không?**
Có, nếu bạn nói ngay ở phỏng vấn: phần ở lại Python vào `Must-NOT-Have`, và cutover chọn strangler-fig. Điều không được phép là _âm thầm_ dừng giữa chừng rồi gọi là xong.

**Agent tự đổi scope được không?**
Không. Executor có thể thêm việc implementation còn thiếu, nhưng đổi intent là việc của bạn — nó phải quay lại `/spec` và xin duyệt lại.
