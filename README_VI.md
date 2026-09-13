# CLAUDART

[English](README.md) · [Hướng dẫn quy trình](docs/WORKFLOW_VI.md)

CLAUDART là một bộ quy trình đặt ngay trong repository dành cho Claude Code, Codex CLI, DeepSeek Harness (`dsh`) và Pi. Trạng thái phiên làm việc, kế hoạch triển khai, kiến thức dự án và chỉ dẫn cho agent đều được lưu bằng Markdown và quản lý cùng mã nguồn.

Bốn lớp Claude, Codex, DeepSeek và Pi hoạt động độc lập. Bạn có thể cài một lớp hoặc nhiều lớp. CLAUDART không cần cơ sở dữ liệu, daemon hay dịch vụ chạy nền.

## CLAUDART bổ sung những gì

- **Định hướng phiên làm việc:** bắt đầu phiên mới từ trạng thái hiện tại, công việc đang mở, kiến thức dự án và lịch sử Git gần nhất.
- **Kế hoạch bền vững:** lưu công việc nhiều bước trong file thay vì để kế hoạch biến mất cùng cuộc trò chuyện.
- **Đặc tả cho công việc lớn:** mô tả và thực thi công việc kéo dài qua nhiều tác vụ hoặc nhiều phiên dưới một đặc tả đã được phê duyệt.
- **Kiến thức dự án:** tách các sự thật bền vững khỏi quy tắc hành vi và trạng thái tạm thời.
- **Bàn giao phiên:** giữ lại phần điều tra đang dở khi cửa sổ ngữ cảnh gần đầy.
- **Công cụ bảo trì:** kiểm tra và chuẩn hóa cấu trúc bộ nhớ mà không cần thêm dịch vụ riêng.
- **Agent chuyên biệt theo yêu cầu:** dùng agent cho chất lượng mã, bảo mật và đánh giá giao diện chỉ khi bạn gọi rõ ràng.

## Cài đặt

### Dự án mới

Mặc định, lệnh sau cài lớp Claude Code:

```bash
curl -fsSL https://raw.githubusercontent.com/lapnd/Claudart/main/install.sh | bash
```

Chọn lớp cần cài khi cần thiết:

```bash
# Claude Code
curl -fsSL https://raw.githubusercontent.com/lapnd/Claudart/main/install.sh | bash -s -- --claude

# Codex CLI
curl -fsSL https://raw.githubusercontent.com/lapnd/Claudart/main/install.sh | bash -s -- --codex

# DeepSeek Harness (dsh)
curl -fsSL https://raw.githubusercontent.com/lapnd/Claudart/main/install.sh | bash -s -- --deepseek

# Pi
curl -fsSL https://raw.githubusercontent.com/lapnd/Claudart/main/install.sh | bash -s -- --pi

# Claude Code và Codex
curl -fsSL https://raw.githubusercontent.com/lapnd/Claudart/main/install.sh | bash -s -- --both

# Cả bốn lớp
curl -fsSL https://raw.githubusercontent.com/lapnd/Claudart/main/install.sh | bash -s -- --all
```

Trình cài đặt sao chép các file còn thiếu và bỏ qua file đã tồn tại. Tùy chọn `--force` sẽ ghi đè file hiện có, vì vậy chỉ dùng khi bạn thực sự muốn thay thế chúng.

### Cài từ một fork

`--repo` và `--branch` quyết định nơi tải lớp về, nên có thể cài từ fork mà không phải sửa script:

```bash
# từ một fork
curl -fsSL https://raw.githubusercontent.com/lapnd/Claudart/main/install.sh | bash -s -- --repo vankhaivn/Claudart --all

# hoặc đặt qua biến môi trường, tiện hơn khi chạy qua pipe
CLAUDART_REPO=vankhaivn/Claudart curl -fsSL https://raw.githubusercontent.com/lapnd/Claudart/main/install.sh | bash -s -- --all
```

Cờ tường minh thắng biến môi trường. Giá trị không đúng dạng `<owner>/<name>` bị từ chối trước khi tải bất cứ thứ gì, nên gõ sai sẽ báo lỗi ngay thay vì hiện ra dưới dạng 404 giữa chừng.

### `AGENTS.md` dùng chung làm bộ định tuyến

Codex, `dsh` và Pi đều tự nạp `AGENTS.md` ở thư mục gốc. Thay vì tranh nhau một tên file, CLAUDART coi nó là bộ định tuyến dùng chung: mỗi lớp giữ chỉ dẫn trong thư mục riêng (`.codex/AGENTS.md`, `.deepseek/DEEPSEEK.md`, `.pi/PI.md`) và trình cài đặt chỉ thêm một dòng trỏ tới đó.

```markdown
<!-- claudart:routes:start -->

- Codex CLI → follow `.codex/AGENTS.md`
- DeepSeek Harness (dsh) → follow `.deepseek/DEEPSEEK.md`
- Pi → follow `.pi/PI.md`

<!-- claudart:routes:end -->
```

Trình cài đặt chỉ ghi bên trong cặp marker này. Nếu dự án của bạn đã có `AGENTS.md`, nội dung cũ được giữ nguyên và khối trên được nối vào cuối. Claude Code không đọc file này; lớp của nó nạp qua `.claude/CLAUDE.md`.

`.agents/skills/` cũng dùng chung cho cả ba harness. Trình cài đặt chỉ sao chép skill của lớp bạn yêu cầu, nên bản cài một lớp luôn sạch; khi cài nhiều lớp, mọi harness đều thấy đủ các tiền tố (`codex-*`, `deepseek-*`, `pi-*`) và bạn gọi đúng tiền tố của lớp mình.

### Dự án đã có cấu hình hoặc đã cài CLAUDART

Không dùng trình cài đặt như một công cụ hợp nhất. Nó có thể sao chép hoặc ghi đè file, nhưng không đối soát được chỉ dẫn tùy chỉnh, trạng thái đang dùng, tác vụ, đặc tả hay kiến thức riêng của dự án.

Hãy yêu cầu coding agent làm theo quy trình tích hợp:

> Đọc https://raw.githubusercontent.com/lapnd/Claudart/main/INTEGRATE.md và làm theo để tích hợp hoặc cập nhật CLAUDART trong dự án này. Giữ nguyên nội dung riêng của dự án và trình bày các thay đổi dự kiến trước khi ghi file.

Quy trình này so sánh dự án hiện tại với nhánh `main` mới nhất, đồng thời phân biệt file CLAUDART đã cũ với nội dung do dự án tự viết.

### Lần chạy đầu tiên

Sau khi cài hoặc đối soát, chạy một lần chuỗi kiểm tra và chuẩn hóa:

| Claude Code        | Codex CLI                | DeepSeek (dsh)              | Pi                          |
| ------------------ | ------------------------ | --------------------------- | --------------------------- |
| `/doctor`          | `$codex-doctor`          | `/deepseek-doctor`          | `/skill:pi-doctor`          |
| `/refactor-memory` | `$codex-refactor-memory` | `/deepseek-refactor-memory` | `/skill:pi-refactor-memory` |
| `/doctor`          | `$codex-doctor`          | `/deepseek-doctor`          | `/skill:pi-doctor`          |

Sau đó bắt đầu phiên làm việc bình thường bằng `/start`, `$codex-start`, `/deepseek-start` hoặc `/skill:pi-start`.

## Quy trình hằng ngày

| Mục đích                                               | Claude Code        | Codex CLI                | DeepSeek (dsh)              | Pi                          |
| ------------------------------------------------------ | ------------------ | ------------------------ | --------------------------- | --------------------------- |
| Định hướng phiên                                       | `/start`           | `$codex-start`           | `/deepseek-start`           | `/skill:pi-start`           |
| Tạo kế hoạch triển khai bền vững                       | `/plan <task>`     | `$codex-plan <task>`     | `/deepseek-plan <task>`     | `/skill:pi-plan <task>`     |
| Mô tả công việc lớn, kéo dài nhiều phiên               | `/spec <mission>`  | `$codex-spec <mission>`  | `/deepseek-spec <mission>`  | `/skill:pi-spec <mission>`  |
| Thực thi đặc tả đã được phê duyệt                      | `/spec-run <slug>` | `$codex-spec-run <slug>` | `/deepseek-spec-run <slug>` | `/skill:pi-spec-run <slug>` |
| Lưu phần điều tra đang dở                              | `/handoff`         | `$codex-handoff`         | `/deepseek-handoff`         | `/skill:pi-handoff`         |
| Xây dựng lại trạng thái hiện tại tại điểm dừng phù hợp | `/checkpoint`      | `$codex-checkpoint`      | `/deepseek-checkpoint`      | `/skill:pi-checkpoint`      |
| Biến cách làm lặp lại thành quy tắc                    | `/learn`           | `$codex-learn`           | `/deepseek-learn`           | `/skill:pi-learn`           |
| Kiểm tra bản cài đặt                                   | `/doctor`          | `$codex-doctor`          | `/deepseek-doctor`          | `/skill:pi-doctor`          |

Dùng kế hoạch tác vụ cho phần triển khai có nhiều bước hoặc nhiều file. Dùng đặc tả khi công việc có nhiều giai đoạn, cần bản thử nghiệm hoặc tiêu chí nghiệm thu, hay phải tiếp tục qua nhiều phiên.

## Cách tổ chức trạng thái

| Vị trí                      | Mục đích                                         | Cách nạp                                            |
| --------------------------- | ------------------------------------------------ | --------------------------------------------------- |
| `CONTEXT.md`                | Trạng thái hiện tại của dự án và công việc       | Đọc khi bắt đầu phiên; được checkpoint viết lại     |
| `JOURNAL.md`                | Lịch sử đã kết thúc                              | Chỉ nối thêm; không tự động nạp                     |
| `rules/` hoặc `guidelines/` | Chỉ dẫn mang tính quy định cho hành vi của agent | Nạp khi phù hợp                                     |
| `knowledge/`                | Các sự thật bền vững mô tả dự án                 | Định tuyến qua `INDEX.md`; chỉ đọc chi tiết khi cần |
| `tasks/`                    | Kế hoạch triển khai bền vững                     | Đọc khi tác vụ đang hoạt động hoặc được tiếp tục    |
| `specs/`                    | Đặc tả công việc lớn và lịch sử thực thi         | Đọc khi đặc tả đang hoạt động                       |
| `HANDOFF.md`                | Bàn giao suy luận cho một phiên kế tiếp          | Phiên `/start` kế tiếp tiếp nhận rồi xóa            |

Ranh giới quan trọng nhất: **quy tắc nói agent nên làm việc như thế nào; knowledge ghi điều gì đang đúng về dự án; task và spec ghi công việc đang được thực hiện.**

## Agent chuyên biệt

Các agent này không bao giờ tự chạy.

| Agent               | Vai trò                                                                                                                                       |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Clean-code reviewer | Cải thiện chất lượng mã trong phạm vi rõ ràng, giữ nguyên hành vi dự kiến và chạy kiểm tra. Yêu cầu chỉ review sẽ giữ agent ở chế độ chỉ đọc. |
| Security auditor    | Thực hiện audit bảo mật chỉ đọc dựa trên bằng chứng và ghi báo cáo.                                                                           |
| UI visual critic    | Đánh giá giao diện hoặc đầu ra trực quan đã render khi được yêu cầu rõ ràng.                                                                  |

Agent cha vẫn chịu trách nhiệm về phạm vi, tích hợp và kiểm tra kết quả của công việc được giao cho subagent.

## Phát triển CLAUDART

Repository này dùng Prettier cho Markdown và các kiểm tra Bash cho trình cài đặt, hợp đồng knowledge và quy trình spec.

```bash
npm ci
npm run check
```

Để dùng pre-commit hook của repository:

```bash
npm run hooks:install
```

## Tài liệu

- [Hướng dẫn quy trình](docs/WORKFLOW_VI.md)
- [Workflow guide bằng tiếng Anh](docs/WORKFLOW.md)
- [Quy trình tích hợp và nâng cấp](INTEGRATE.md)
- [Hướng dẫn đóng góp](CONTRIBUTING.md)

## Giấy phép

CLAUDART được phát hành theo [giấy phép MIT](LICENSE).
