<!-- AI agents: human-oriented pitch. The binding contracts live in .claude/rules/ and .codex/guidelines/ — read those, not this file, when acting. -->

<div align="center">
  <h1>CLAUDART</h1>
  <p><strong>Lớp vận hành bằng markdown cho Claude Code &amp; Codex CLI - memory, kế hoạch và review, tất cả nằm trong git.</strong></p>

  <p>
    <a href="https://github.com/lapnd/Claudart/blob/main/LICENSE"><img alt="License" src="https://img.shields.io/github/license/lapnd/Claudart?style=for-the-badge&color=orange"></a>
    <img alt="Pure Markdown" src="https://img.shields.io/badge/memory-pure_markdown-blue?style=for-the-badge">
    <img alt="Offline-friendly" src="https://img.shields.io/badge/works-offline-green?style=for-the-badge">
    <a href="https://github.com/lapnd/Claudart/issues"><img alt="Issues" src="https://img.shields.io/github/issues/lapnd/Claudart?style=for-the-badge&color=blue"></a>
  </p>
</div>

---

Coding agent hay quên. Đóng terminal là kế hoạch biến mất. Session kế tiếp bắt đầu trong mù mờ, đọc lại nửa repo, rồi tranh luận lại một quyết định bạn đã chốt từ thứ Ba tuần trước. Trong lúc đó `CLAUDE.md` cứ phình to, vì chẳng ai đủ tin nó để xóa bất kỳ thứ gì.

CLAUDART xử lý chuyện này bằng file. Một nhóm slash command nhỏ duy trì một bộ tài liệu markdown dưới `.claude/` và `.codex/`: điều đang đúng ngay lúc này, kế hoạch cho từng task, các fact và rule đáng giữ lại. Tất cả đều được commit vào git, review được trong PR, và đọc được mà không cần tooling nào. Không có vector database, không daemon. Không cần host, không cần trông coi.

## Cài đặt

```bash
# Flag sau `bash -s --`:  --claude (mặc định) · --codex · --both · --upgrade (làm mới file template; không đụng live state) · --force (ghi đè tất cả) · --council (cài thêm companion /council, phạm vi user) · --repo=<owner/name> (cài từ fork; env CLAUDART_REPO — chạy local tự phát hiện origin của checkout)
curl -fsSL https://raw.githubusercontent.com/lapnd/Claudart/main/install.sh | bash -s -- --claude
```

Để cập nhật một install đã có lên template mới nhất (live state và `CLAUDE.md`/`AGENTS.md` bạn đã custom không bao giờ bị đụng - commit trước, review bằng `git diff`, rồi chạy `/doctor`):

```bash
curl -fsSL https://raw.githubusercontent.com/lapnd/Claudart/main/install.sh | bash -s -- --upgrade   # tự phát hiện layer; thêm --claude/--codex/--both để override
```

`install.sh` copy mới toàn bộ, và đó không phải cách đúng cho một project đã có setup riêng. Trong trường hợp đó, hãy dán đoạn này vào agent của bạn. Nó sẽ đọc repo, diff với project, và chỉ merge những gì bạn phê duyệt:

> Đọc https://raw.githubusercontent.com/lapnd/Claudart/main/INTEGRATE.md và làm theo để tích hợp CLAUDART vào project này. Hỏi tôi trước khi đụng tới bất kỳ thứ gì tôi đã custom.

Installation hiện hữu dùng `INTEGRATE.md` để derive delta thực tế với upstream hiện tại, không giả định bản khởi đầu. Với knowledge contract đang được upstream khai báo, flow đối soát là `doctor → refactor-memory → doctor`; workflow này không có thêm command recall hay migration riêng.

## CLAUDART giải quyết gì

| Nỗi đau                                      | Cách CLAUDART xử lý                                                                                                                                                 |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Session nào cũng bắt đầu mù mờ               | `/start` đọc trạng thái hiện tại, task đang mở và các commit gần đây trước khi đụng vào bất kỳ thứ gì                                                               |
| Kế hoạch mất khi session đóng                | `/plan` ghi kế hoạch vào task file để session sau có thể tiếp tục đúng chỗ bạn dừng                                                                                 |
| Mission quá lớn cho một session hay một plan | `/spec` đóng băng ý định thành POC + roadmap bạn approve một lần; `/spec-run` chạy lặp tới final review                                                             |
| Refactor không được phép đổi hành vi         | `/refactor` ghim baseline, viết behavior contract + blast radius, và chứng minh tương đương                                                                         |
| Viết lại sang ngôn ngữ hoặc UI stack khác    | `/migrate` đóng băng API seam và bảng translation-rules của chính dự án, rồi chứng minh parity bằng cách chạy song song hai stack ([hướng dẫn](docs/MIGRATE_VI.md)) |
| Session hiệu quả chạm trần context           | `/handoff` lưu suy luận của session - giả thuyết, evidence, dead ends - cho lần `/start` kế tiếp                                                                    |
| Cùng quyết định bị tái khám phá hằng tuần    | `/learn` biến correction hành vi lặp lại thành rule có scope theo path                                                                                              |
| Fact bền của dự án không có chỗ đúng để sống | `knowledge/` lập map; agent nạp map phù hợp, outline topic rồi chỉ section liên quan                                                                                |
| `CLAUDE.md` phình thành bồn đốt token        | `/refactor-memory` gọt nó lại thành một index và đưa nội dung về đúng nơi                                                                                           |
| Memory âm thầm mục ruỗng                     | `/doctor` chạy checker read-only được ship sẵn, rồi audit drift ngữ nghĩa và nội dung đặt sai tầng                                                                  |
| Đổi máy, hoặc mang context sang project khác | `/backup` xuất bundle portable; `/restore` merge sang nơi khác mà không bao giờ ghi đè file có sẵn                                                                  |

Ba review agent được ship kèm các command - `clean-code-reviewer`, `security-auditor` và `ui-visual-critic`, mỗi cái chỉ chạy khi được yêu cầu rõ ràng (không bao giờ tự động, kể cả bên trong một task hay spec loop) - cùng một delegation protocol để giữ việc subagent song song có biên rõ ràng thay vì lan rộng mất kiểm soát.

## Mô hình memory

Bốn loại memory, bốn vòng đời khác nhau:

```text
SESSION STATE (dễ bay hơi)           DURABLE REFERENCE (sống qua session)

CONTEXT.md       JOURNAL.md          rules/ · guidelines/   knowledge/
điều đang đúng   điều đã xảy ra      cách hành xử           dự án là gì
(declarative)    (history log)       (prescriptive)         (descriptive facts)

luôn được load   không được load     auto-load theo         INDEX trên /start,
vào context      (chỉ audit)         path phù hợp           chi tiết đọc khi cần
```

`/checkpoint` rebuild `CONTEXT.md` cuối session, retire lịch sử sang `JOURNAL.md`, và bulk-promote các fact bền còn lại. Nó không phải write boundary duy nhất: giữa một lượt explore dài, nói “hãy cập nhật knowledge từ phần vừa xác minh rồi tiếp tục” sẽ kích hoạt distillation ngay. Fact dự án current và đã verify vào `knowledge/`; task/WIP/proposed state ở lại task, spec hoặc context; claim chưa chắc vẫn là candidate, trừ khi evidence làm mất hiệu lực owner hiện có thì topic đó chuyển thành `review-needed`; behavior lặp lại đi vào rule qua `/learn`.

Retrieval đi từ map và có budget: root `INDEX.md`, tối đa các domain map phù hợp, rồi frontmatter/outline topic và section nhỏ nhất đủ dùng. Đọc toàn file hay search history/source chỉ là fallback. `/doctor` và `/refactor-memory` tự gọi Bash checker không dependency; user không phải kẹp thêm command vào prompt thường ngày.

## Bắt đầu nhanh

```bash
# Trong project đã cài CLAUDART
/start                          # định hướng session
/plan add JWT middleware        # ghi task file; agent chờ bạn approve trước khi code
/spec build the demo game       # mission quá lớn cho một plan? phỏng vấn → POC → roadmap, approve một lần
/spec-run demo-game             # session mới thực thi mission đã approve tự chủ tới cổng final review
/refactor migrate auth to v2    # mission refactor: baseline ghim + behavior contract chứng minh tương đương
/migrate nicegui app to go+vue  # mission port: seam contract-first, translation rules, parity chạy song song
/prove sửa lỗi phân trang       # evidence-first: đỏ trước xanh, chạy gauntlet, báo cáo bằng số liệu
/handoff                        # context gần đầy? lưu suy luận, resume fresh bằng /start
/checkpoint                     # rebuild CONTEXT.md cuối session
/learn                          # thăng cấp quyết định lặp lại thành rule
/doctor                         # health check khi setup có vẻ lệch
/optimize                       # auto-compact quá thường xuyên? audit xem token đi đâu
/backup                         # đổi máy? xuất session + memory thành bundle portable
/restore                        # nhập bundle đó ở nơi khác - dry run trước, không bao giờ ghi đè
```

Codex CLI chạy cùng flow với `$codex-` thay cho `/` (ví dụ `$codex-start`).

## Tài liệu

**[docs/GUIDE.md](docs/GUIDE.md)** là cookbook (tiếng Anh) - chọn tình huống, làm theo công thức: walkthrough cụ thể cho từng command và kịch bản.
**[docs/WORKFLOW_VI.md](docs/WORKFLOW_VI.md)** là manual - kiến trúc, lifecycle đầy đủ của task, toàn bộ command và layout thư mục. README này chỉ là phần giới thiệu.

Bản tiếng Anh: **[README.md](README.md)** và **[docs/WORKFLOW.md](docs/WORKFLOW.md)**.

## So sánh

|                                |        CLAUDART        |              Mem0               |          Zep          |        LangMem        |              Understand-Anything               |                     MemPalace                      |
| ------------------------------ | :--------------------: | :-----------------------------: | :-------------------: | :-------------------: | :--------------------------------------------: | :------------------------------------------------: |
| **Setup**                      |     `curl \| bash`     | vector DB + Docker + OpenAI key | Neo4j + managed cloud | PostgreSQL + pgvector |           `curl \| bash` hoặc plugin           |            `pip install` + model 300 MB            |
| **Con người đọc được**         |           ✅           |               ❌                |          ❌           |          ❌           |              ⚠️ JSON + dashboard               |           ⚠️ text nguyên văn, binary DB            |
| **Chạy offline / air-gapped**  |           ✅           |               ❌                |          ❌           |          ❌           |                   ❌ cần LLM                   |                         ✅                         |
| **Memory review được bằng PR** |           ✅           |               ❌                |          ❌           |          ❌           |             ✅ JSON commit vào git             |            ❌ ChromaDB + SQLite binary             |
| **Tool hỗ trợ**                | Claude Code, Codex CLI |             chỉ API             |        chỉ API        |     chỉ LangGraph     | Claude, Codex, Cursor, Copilot, Gemini + 6 nữa | Claude Code, Codex CLI, Gemini CLI, MCP-compatible |

Markdown thuần trong repo đã thắng lập luận này: `AGENTS.md` cung cấp một convention có version mà nhiều coding agent có thể dùng chung. CLAUDART xây workflow còn thiếu ở phía trên - orientation, planning, learning, hygiene và review.

## License

MIT, xem [`LICENSE`](LICENSE). Hoan nghênh đóng góp; [`CONTRIBUTING.md`](CONTRIBUTING.md) có các nguyên tắc cơ bản.
