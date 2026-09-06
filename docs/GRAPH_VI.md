<!-- AI agents: this is a human-oriented manual. The binding contracts are .claude/rules/graph-development.md and .claude/knowledge/graph-model.md — read those, not this file, when acting. Read this file only when the user asks how the development graph works. -->

# `/graph` — đồ thị phát triển (development graph)

`/graph` điều khiển `.claude/scripts/claudart-graph.sh`, một engine Python-stdlib biến manifest
`architecture.yaml` cùng `ROADMAP.md` dạng graph của một spec mission thành một đồ thị phụ thuộc thực
thi được: nó lên lịch công việc thành từng wave, giao cho worker một brief tự chứa, và ghi lại mỗi
transition trạng thái dưới dạng event do orchestrator quan sát. Nó không bao giờ sửa `ROADMAP.md`,
`SPEC.md`, hay source code của bạn - file duy nhất nó ghi là `<spec>/graph/events.jsonl` và
`<spec>/graph/evidence/*.log`.

Tài liệu này mô tả engine cho **bất kỳ project nào** nó chạy trên đó - đồ thị mô hình hóa kiến trúc
hexagonal của chính project đó, không bao giờ là của CLAUDART. `/spec` phát ra một mission graph-ready
khi nó decompose một hexagon; `/spec-run` tự động chạy nó ngay khi `architecture.yaml` tồn tại (xem
`spec-workflow.md` → "Graph-driven iteration"). Dùng `/graph` trực tiếp để lint, kiểm tra, hoặc debug
đồ thị của một mission giữa các vòng lặp.

## 1. Manifest — `architecture.yaml`

Một tập con YAML nhỏ (không tab, không flow mapping, không anchor) mô tả hexagon mục tiêu:

```yaml
version: 1
project: example-catalog
profile: hexagonal # hexagonal | debug | library

layout:
  domain: internal/domain
  usecases: internal/app
  ports: internal/ports
  adapters: internal/adapters
  composition: cmd

rules:
  forbid:
    - from: adapter
      to: adapter
    - from: domain
      to: adapter

architecture:
  budget: 0 # debt ratchet - chỉ đổi khi có re-measurement, không bao giờ sửa tay
```

`domains`, `usecases`, `ports` (kèm `direction: in|out`), và `adapters` (mỗi cái nêu tên `port` nó
implement) hoàn thiện các cây layout. `rules.forbid` là thứ `lint`/`drift`/`gate` dùng để check hướng
phụ thuộc; `architecture.budget` là một ratchet, phải khớp chính xác theo cả hai chiều.

## 2. Metadata node trong ROADMAP

Mỗi task trong ROADMAP mang metadata thụt 6 space dưới checkbox của nó:

```markdown
- [ ] P1.1 Catalog domain entities and invariants (verify: go test ./internal/domain/catalog/...) (tier: standard)
      node: domain/catalog | kind: domain
      requires: test/domain-catalog (TEST)
      paths: internal/domain/catalog/\*\*
```

`node: <kind>/<name>` là id. `requires: <dep> (TYPE)` liệt kê các edge phụ thuộc; `proves:` đánh dấu
node test mà một implementation sẽ chuyển sang xanh khi `done`. `paths:` gán node vào các file thật
(dùng để phát hiện merge-risk). Tùy chọn: `tier:` (routing, theo `agent-delegation.md`), `forbid:`
(cấm cục bộ thêm), `exclusive:` (không bao giờ chạy đồng thời với node khác), `early-ok:` (miễn cho
một node ở phase sau, không có `requires:`, khỏi bị check orphan).

## 3. Kind — vai trò hexagonal, lấy từ profile của manifest

Kind không phải free text; `profile` của manifest cung cấp bộ từ vựng:

- **`hexagonal`**: domain, usecase, port, adapter, contract, mock, composition, test, merge, gate, spike
- **`debug`**: repro, hypothesis, fix, test, merge, gate, spike
- **`library`**: module, api, test, merge, gate, spike

## 4. Loại edge — đồ thị là một DAG

Các loại edge đã đăng ký: `IMPLEMENTATION`, `CONTRACT`, `PORT`, `DATA`, `RUNTIME`, `TEST`,
`DEPLOYMENT`, `EVIDENCE`. Wave được **tính toán** từ các edge này, không bao giờ khai báo tay - một
heading `## Phase N` là mốc cho người đọc, không phải chỉ dẫn lập lịch. Đồ thị phải acyclic.

## 5. Brief — thứ duy nhất worker được thấy

```bash
bash .claude/scripts/claudart-graph.sh brief <node> --dir <spec>
```

Brief là một gói tự chứa, có ngân sách byte (`brief.max_bytes` trong manifest): claim của node, lệnh
verify của nó, trạng thái của từng input - và với node test, nó phải đang fail hay đang pass. Worker
không bao giờ nhận `ROADMAP.md` hay `architecture.yaml` thô, và không ghi gì dưới spec folder: không
tick, không dòng LEDGER, không graph event, và không bao giờ tự ghi `done` của chính nó.

## 6. Event log — trạng thái là một fold, không bao giờ là file mutable

Trạng thái được fold từ `<spec>/graph/events.jsonl`, file duy nhất engine append vào, và **chỉ
orchestrator** được ghi - một worktree spawn cho worker thậm chí không thấy được spec folder (đã
gitignore). Node test đi qua `pending → red → green`: `red` cần một exit khác 0 đã quan sát được, và
`green` không bao giờ xảy ra nếu chưa có `red` trước đó. Event `done` của một implementation tự động
chuyển các test nó `proves` từ `red` sang `green`.

## 7. Exit-code contract

`0` clean / open / accepted · `1` findings / closed / refused · `2` usage / parse failure. Mọi lint
finding đều được đăng ký cùng rule clause nó enforce - chạy `claudart-graph.sh rules` để tra cứu.

## 8. Workflow red → green

Architecture → test (đã quan sát red) → implementation, được enforce có cấu trúc thay vì bằng quy ước:

```bash
bash .claude/scripts/claudart-graph.sh lint --dir <spec>                       # parse + báo cáo finding
bash .claude/scripts/claudart-graph.sh schedule --dir <spec> --root <repo>     # wave, merge risk, shape
bash .claude/scripts/claudart-graph.sh next --dir <spec> --root <repo>         # cái gì sẵn sàng ngay lúc này
bash .claude/scripts/claudart-graph.sh brief <node> --dir <spec>               # input duy nhất của worker
bash .claude/scripts/claudart-graph.sh event <test-node> red --run --dir <spec> --root <repo>
bash .claude/scripts/claudart-graph.sh event <node> done --run --dir <spec> --root <repo>
```

`event <node> <state> --run` chạy lại chính `verify:` của node đó và ghi lại exit mà orchestrator thật
sự quan sát được - exit do worker tự khai không bao giờ được tin, luôn bị từ chối. Với một project
brownfield chưa có manifest, `audit` scan cây thật và phát ra một `architecture.yaml` đã seed (budget
= số vi phạm đo được) cùng một `refactor-plan.md` test-first:

```bash
bash .claude/scripts/claudart-graph.sh audit --root <tree> --out <dir>
```

`retro --dir <spec>` sinh các tín hiệu retrospective deterministic (thời gian chạy verify, số lần
reopen/retry, chi phí theo tier) để `/learn` tiêu thụ lúc rotation hoặc đóng mission.

Xem `.claude/rules/graph-development.md` để có bộ rule đầy đủ và `.claude/knowledge/graph-model.md`
cho data model mà tài liệu này tóm tắt.
