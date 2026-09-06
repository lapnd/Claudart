# Trí tuệ cá nhân như một "nhà nước số" có quản trị — Tóm tắt nghiên cứu

Bản tóm tắt tiếng Việt của [`README.md`](README.md) (báo cáo đầy đủ, 17 mục), [`landscape.md`](landscape.md) (khảo sát công nghệ, ma trận năng lực) và [`poc.md`](poc.md) (thiết kế POC). Ngày 2026-09-06.

## Kết luận ngắn

**Làm được, và khoảng hai phần ba đã có sẵn dưới dạng có thể ghép lại.** Phép ẩn dụ "quốc gia" là một _lăng kính thiết kế_ tốt nhưng là một _bản vẽ triển khai_ tồi. Phần thực sự còn thiếu rất nhỏ: (1) một lược đồ cho "luật" mang cấp thẩm quyền, trạng thái vòng đời, phạm vi, bộ cưỡng chế và bằng chứng; (2) một _trình biên dịch_ từ một nguồn luật duy nhất ra định dạng của mọi agent cộng với các bộ cưỡng chế xác định (hook, lint, CI); (3) một _sổ đề bạt_ đếm bằng chứng từ bài học → luật → nguyên tắc, do con người phê duyệt. Mọi thứ còn lại (lưu trữ, phiên bản, review, phân phối, truy xuất, cưỡng chế) giao cho Git, Markdown có cấu trúc, hook, linter và cơ chế nạp ngữ cảnh sẵn có của các agent.

## Ba loại nội dung, ba nền tảng khác nhau

Phát hiện quan trọng nhất: "lớp trí tuệ" không phải là một thứ. Nó chứa ba loại nội dung với tốc độ thay đổi, thẩm quyền và cách truy xuất khác nhau:

| Loại                                               | Ví dụ                                                         | Nền tảng phù hợp                                                                                           | Cách truy xuất                                                                          |
| -------------------------------------------------- | ------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| **Chuẩn mực** (hiến pháp, luật, quy ước)           | "ưu tiên artifact xác định", "test phải đỏ trước khi cài đặt" | file Markdown nhỏ trong Git, review bằng PR, **biên dịch** ra bộ cưỡng chế và file ngữ cảnh cho từng agent | theo phạm vi + trigger; digest luôn nạp, thân bài chỉ khi cần; bộ cưỡng chế tốn 0 token |
| **Tri thức mô tả** (sự kiện, kiến trúc, thuật ngữ) | "module X sở hữu Y"                                           | Markdown có frontmatter + bộ định tuyến gốc (tiết lộ dần)                                                  | index → map → topic → section                                                           |
| **Sự kiện / bằng chứng** (chuyện gì đã xảy ra)     | ledger, kết quả test, quyết định, sửa lỗi                     | log chỉ-ghi-thêm (JSONL), gập thành trạng thái                                                             | theo truy vấn, không bao giờ nạp cả khối                                                |

Gom cả ba vào "một cơ sở dữ liệu bộ nhớ" là sai lầm gốc.

## Phép ẩn dụ quốc gia: giữ gì, bỏ gì

- **Giữ (chịu lực):** thang thẩm quyền (hiến pháp > luật > quy ước dự án), thủ tục tu chính có ma sát tăng theo cấp, tách "ai viết / ai thực thi / ai phán xử", kho lưu trữ làm bằng chứng.
- **Bỏ:** bầu cử và tính chính danh (chỉ có một chủ thể là bạn), chủ quyền và cưỡng chế (agent không thể bất tuân, cơ chế thật là _cưỡng chế xác định_), công dân, ngoại giao.
- **Nền tảng học thuật tốt hơn:** ba cấp luật của Ostrom (hiến định / lựa chọn tập thể / vận hành) — "cấp cao hơn có phạm vi rộng hơn và khó đổi hơn" — không cần chủ quyền hay bầu cử. Hệ thống đa tác tử chuẩn mực (ISLANDER đặc tả, AMELI cưỡng chế) là tiền lệ tính toán cho "thiết chế" và "toà án".

## Chính phủ kiến tạo, tự học, tự tiến hoá

Đề xuất bổ sung của bạn thay đổi kiến trúc theo hướng đúng. Một chính phủ chỉ huy đọc mọi luật ở mọi quyết định rồi phán xử — đó chính là mô hình tốn token, thiếu nhất quán mà ta muốn thoát. Chính phủ kiến tạo thì:

1. **Tạo điều kiện tuân thủ thay vì phán xử:** sản phẩm của nó là hạ tầng xác định — hook chặn hành vi cấm, checker làm build thất bại, script thay việc hỏi LLM lặp lại, index đưa đúng một luật liên quan lên. Luật nào có thể có bộ cưỡng chế thì phải có; LLM chỉ dành cho phần cần phán đoán.
2. **Học từ chính việc thực thi của mình:** mỗi phiên phát ra sự kiện (sửa lỗi, retry, gate thất bại, leo thang). Đó là nguyên liệu của bài học.
3. **Tự tiến hoá trong khuôn khổ hiến pháp:** công cụ và quy ước dự án đổi hằng ngày, tự động nếu qua gate; luật đổi hằng tháng bằng bằng chứng + phê duyệt của người; hiến pháp đổi hiếm hoi và chỉ do người. **Quyền tự trị giảm khi thẩm quyền tăng.**

## Thang thẩm quyền đề xuất

```
L0 an toàn / ràng buộc nền tảng   (ngoài hệ thống, không ghi đè)
L1 Hiến pháp                       người tu chính
L2 Luật (có bộ cưỡng chế)          bằng chứng + người phê duyệt
L3 Chuẩn tổ chức / nhóm            tổ chức phê duyệt
L4 Quy tắc dự án                   dự án phê duyệt, agent được đề xuất
L5 Repo / máy cục bộ               agent được đổi
L6 Phiên làm việc                  tạm thời
```

Giải quyết xung đột theo thứ tự: cấp cao thắng → cùng cấp thì phạm vi hẹp thắng → cùng phạm vi thì luật _có cưỡng chế_ thắng luật văn xuôi → còn lại thì luật phê duyệt gần nhất thắng và xung đột được ghi thành bài học. Với lớp cưỡng chế: cấm thắng cho phép, mặc định từ chối (ngữ nghĩa đã chứng minh của Cedar); lớp văn xuôi thì nối tiếp, cấp thấp được siết chặt nhưng không được nới lỏng cấp trên.

## CLAUDART đã là một bản mẫu ở quy mô dự án

Kho này đã có hiến pháp (`constitution.md`, thang ưu tiên + 16 quy tắc vàng), luật (rules với trigger + digest), toà án (`constitution-check.sh`, `claudart-graph lint`, fail-closed), kho lưu trữ (LEDGER, JOURNAL, `events.jsonl` chỉ orchestrator ghi), đường tu chính (`/learn`), và quy tắc "mọi MUST phải gắn bộ cưỡng chế hoặc ghi rõ là phán đoán". Thiếu: lớp _cá nhân_ phía trên dự án, metadata máy đọc được trên luật (cấp, trạng thái, bằng chứng), bước biên dịch-phân phối (mirror Codex đang duy trì tay), và bộ đếm bằng chứng biến "tôi nghĩ việc này lặp lại" thành "lặp 4 lần ở 3 dự án".

## Khảo sát công nghệ — kết quả chính

- **Bộ nhớ agent** (Mem0, Letta, Graphiti, LangMem, Cognee, MemOS, claude-mem, mcp-memory-service, Basic Memory, PLUR, Statewave…): lưu sự kiện + truy xuất vector là hàng phổ thông; hiệu lực song thời (bi-temporal) có ở Graphiti/Statewave; bộ nhớ thủ tục là loại riêng ở vài dự án; **không dự án nào mô hình hoá cấp thẩm quyền, máy trạng thái đề xuất→phê duyệt, hay luật gắn bằng chứng.** Gần nhất về hình dạng: PLUR (YAML trong git, đa công cụ, MCP — đã kiểm chứng trực tiếp) và Basic Memory (Markdown + index + MCP, chín hơn).
- **Tri thức có phiên bản, local-first** (git+Markdown, MADR, Jujutsu, Dolt, TerminusDB, XTDB, CouchDB, Syncthing, CRDT): git + lược đồ frontmatter có kiểm tra + index gập là sàn và đủ ở quy mô này; Dolt là DB đầu tiên đáng cân nhắc nếu truy vấn/merge có cấu trúc thành vấn đề đo được; CRDT và dịch vụ sync không cần cho luồng agent-ghi-file bất đồng bộ.
- **Policy engine và cưỡng chế** (OPA, Cedar, Cerbos, OpenFGA, ast-grep, Semgrep, CUE, hook Claude Code, AGENTS.md, Ruler, rulesync): Cedar là engine duy nhất phát hiện xung đột tĩnh có chứng minh; ast-grep (hoặc Semgrep) là checker cấu trúc; hook `PreToolUse` của Claude Code và CI sau branch protection là hai điểm cưỡng chế không thể bỏ qua; Ruler/rulesync biên dịch một nguồn văn xuôi ra mọi agent nhưng **không tạo hook, permission, policy bundle hay lint pack, không mã hoá thứ tự ưu tiên, không kiểm tra xung đột**.
- **Giao thức:** MCP resource là primitive đúng cho "máy chủ luật" (chưa có cái nào được dùng rộng; roots đã bị deprecate); MCP/A2A/ACP không biểu đạt thẩm quyền, phiên bản hay audit.
- **License:** theo quyết định của bạn (2026-09-06), lớp này là công cụ nội bộ, không nhúng hay phân phối cùng sản phẩm, nên GPL/AGPL (và BSL/SSPL khi dùng cục bộ) không phải rào cản; license chỉ ghi để tham khảo. Nhờ vậy Basic Memory (Markdown + SQLite index + MCP, tích hợp Obsidian) trở lại là tham chiếu mạnh bên cạnh PLUR; Neo4j CE, Semgrep dùng thoải mái. Quy tắc license duy nhất còn hiệu lực là về cây phụ thuộc của _sản phẩm_, thuộc luật của dự án. Bẫy còn lại: Zep đã bỏ bản tự host.

## Kiến trúc và stack đề xuất

Git + Markdown + frontmatter có kiểm tra cho chuẩn mực và tri thức; JSONL chỉ-ghi-thêm cho sự kiện; **trình biên dịch** (sản phẩm của chính phủ kiến tạo) giải quyết ưu tiên → kiểm tra xung đột → phát ra bộ cưỡng chế (hook, permission, ast-grep, CI) + văn xuôi (`CLAUDE.md`, `.claude/rules` có `paths:`, `AGENTS.md`, `.cursor/rules`) + index; kho lưu trữ do orchestrator ghi; sổ đề bạt gập bài học và tạo PR đề xuất khi vượt ngưỡng (mặc định ≥3 bài học ở ≥2 dự án), người merge. Giai đoạn sau: MCP server chỉ-đọc cho agent không đọc file; overlay tổ chức. Từ chối lúc này: vector DB, graph DB, memory server, dịch vụ sync, ngôn ngữ luật mới, LLM làm giám khảo trong đường tuân thủ, tự động đề bạt luật.

## POC nhỏ nhất

Hai dự án, bốn tuần, một lược đồ (frontmatter luật), một log (bài học), một họ script (compile + tally), một lệnh adopt. Năm giả thuyết có thể bác bỏ: H1 biên dịch được ra mọi agent không cần mirror tay; H2 cưỡng chế thay văn xuôi giảm ≥30% token khởi động và bắt ≥50% vi phạm bằng máy; H3 dự án thứ hai bắt đầu không từ số không; H4 đề xuất có đếm bằng chứng được chấp nhận nhiều hơn `/learn` không hỗ trợ; H5 thang ưu tiên đủ xử lý xung đột ở dưới 200 luật. Mỗi chỉ số có đối chứng âm.

## Trả lời bảy câu hỏi

- **A. Tên gọi:** nửa cơ chế là _governed agent memory_, nửa chuẩn mực là _constitutional memory architecture_; nền tảng hình thức là ba cấp luật của Ostrom. Báo cáo dùng tên làm việc **Governed Personal Intelligence** — "một hiến pháp cá nhân có phiên bản, gác bằng bằng chứng, được thực thi như bộ nhớ agent có quản trị".
- **B. Đã giải rồi chưa:** chưa. Từng mảnh có; không đâu ghép đủ thẩm quyền phân tầng + vòng đời đề xuất→phê duyệt do người + đề bạt gắn bằng chứng + thực thi nhất quán đa agent. Kho này là bản mẫu gần nhất, ở quy mô dự án.
- **C. Tổ hợp đủ dùng:** như mục stack ở trên.
- **D. Thiếu thật sự:** lược đồ luật, trình biên dịch, sổ đề bạt.
- **E. Kiến trúc:** ba loại nội dung trên ba nền tảng; compiler là sản phẩm của chính phủ kiến tạo; kho lưu trữ chỉ orchestrator ghi; nghị viện là thủ tục đếm bằng chứng; toà án phần lớn là checker.
- **F. POC:** xem trên.
- **G. Không nên xây:** memory database, vector/graph store, DSL luật, dịch vụ sync, framework agent mới, MCP server trước khi đường file được chứng minh, LLM giám khảo trong đường tuân thủ, tự động đề bạt luật.

## Phản biện của Hội đồng (2026-09-06)

Báo cáo đã qua `/council` với bảy góc nhìn (Socrates, Ada, Meadows, Machiavelli, Taleb, Torvalds, Karpathy); phán quyết đầy đủ ở [`council-review.md`](council-review.md). Kết luận: đáng xây, nhưng có **một lỗi cấu trúc**: vòng đời chỉ có đường thăng cấp mà không có đường _về hưu_ hoạt động được, vì bộ cưỡng chế chạy tốt sẽ triệt tiêu đúng các tín hiệu (ghi đè, mâu thuẫn) mà §10 dựa vào để hạ cấp luật; và người duyệt duy nhất là nút thắt mà mọi cách sửa đều dồn vào. Bốn bổ sung bắt buộc: trường suy giảm/về hưu trong lược đồ luật đi cùng commit với lược đồ; chốt chặn năng lực người duyệt đi cùng; tách `enforcer` khỏi trọng số thẩm quyền ở §2.4; bỏ trường `confidence`. Nâng cấp ý tưởng: **"không gì tự thăng cấp, và không gì tự cố thủ trong im lặng"**, đo thành công bằng giờ-người-duyệt ròng thay vì token tiết kiệm. Câu hỏi mở giá trị nhất: đếm số xung đột luật thật giữa các cấp trong lịch sử repo; nếu bằng 0 thì bộ máy ưu tiên là giải pháp cho một vấn đề không tồn tại. **Đã áp dụng thành bản v2** cùng ngày: trường `authority` tách khỏi `enforcer`; `stale_after` bắt buộc trên mọi luật với suy giảm mềm khi hết hạn (về `draft`, enforcer chỉ cảnh báo sau 30 ngày ân hạn, một mục vào hàng đợi; phân bậc theo `authority`: luật `core` về an toàn không bao giờ hạ dưới mức chặn, chỉ vào hàng đợi; `standard` hạ xuống cảnh báo sau 30 ngày ân hạn; `provisional` cảnh báo ngay); `budget.yaml` giới hạn tốc độ đề xuất, đề xuất hết hạn sau 30 ngày; bỏ `confidence`, thêm `signal` và `matched_against`, đo độ nhất quán phân loại từ tuần đầu; thay catch-rate bằng seeded-violation recall; thêm H6 (về hưu ≤30 ngày) và H7 (giờ-người-duyệt ròng ≤0); compiler tự chặn quá bước 3 nếu chưa có file bằng chứng; pin phiên bản thay vì pull lúc mở phiên.

**OKF:** chuẩn Open Knowledge Format v0.2 của Google Cloud (Apache-2.0) đã chuẩn hoá `verified.by: human:<id>` (bậc tin cậy), `stale_after` (chính là trường về hưu Hội đồng đòi), và "attested computation" với bộ kiểm tra xác định — nên dùng làm chuẩn frontmatter cho lớp tri thức và tái dùng trên luật. Công cụ `okf-agent-memory` (MIT, Go): **bạn đã quyết định dùng cho lớp tri thức.** Đã thử tại chỗ: build được, test pass, `validate` fail-closed (thiếu `type` → exit 1), search BM25 và bootstrap chạy, MCP bắt tay được với 6 tool. Hai lưu ý: MCP có tool ghi nên chỉ chạy trên `knowledge/`, không bao giờ trên `laws/`; dự án mới hai commit một tác giả nên file vẫn là nguồn sự thật, kiểm lại hằng tháng.

## Quyết định 2026-09-06 (bạn giao: chọn cái đúng và tốt lâu dài)

- **Hết hạn luật:** suy giảm mềm, phân bậc theo `authority` như trên. Lý do: thang Hiến pháp đặt đúng đắn và an toàn trên hết — một bộ cưỡng chế an toàn không được lặng lẽ ngừng bảo vệ, và một luật thường sai không được chặn mãi mãi; chỉ người mới được khai tử luật.
- **Đếm xung đột (tiêu chí huỷ số 1 của Hội đồng):** đã quét rules, JOURNAL, specs, tasks và lịch sử git ([`conflict-count.md`](conflict-count.md)). Kết quả: **3 va chạm thật** (trailer Co-Authored-By của harness vs `git-commits.md`; cổng duyệt từng task vs phê duyệt một lần của spec; quy tắc uỷ thác cũ vs hành vi harness) cộng 3 điều khoản ưu tiên viết sẵn. Điểm quyết định: **cả sáu đều được người giải quyết lúc viết luật bằng một câu "overrides / supersedes / this file wins", không ca nào ở runtime.** Vì vậy ưu tiên là việc của trình biên dịch, không phải bộ giải lúc chạy: luật có phạm vi chồng nhau phải khai báo `overrides:` / `supersedes_in_scope:` / `layers_on:`, compiler fail-closed nếu chồng mà không khai; thang L0–L6 chỉ dùng để bác khai báo trái luật (cấp dưới được siết, không được nới) và sắp thứ tự văn xuôi; bộ cưỡng chế vẫn ghép bằng phép hội. Đây là kết luận của Socrates giữ lại thang làm luật cho các checker, và thu hẹp phần phải xây so với v1.

## Điều chưa kiểm chứng

Đã kiểm trực tiếp: PLUR, Statewave (cửa sổ hiệu lực và rollback _không_ thấy trên README), arXiv:2603.04740. Chưa tự kiểm lại: một số mốc ngày 2026 (Zep bỏ CE, Kyverno graduate, MCP roots deprecate), license ElectricSQL, tình trạng bảo trì cr-sqlite, MCP của TerminusDB, toàn văn khảo sát "Always-On Agents" và "Governed Memory". "Không có MCP policy server nào được dùng rộng" là kết quả tìm kiếm âm, không phải chứng minh.
