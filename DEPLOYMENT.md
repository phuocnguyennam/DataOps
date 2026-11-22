# DEPLOYMENT.md — Hướng dẫn triển khai & vận hành (Runbook)

Tài liệu này mô tả quy trình **Continuous Deployment (CD)** của dự án: cách pipeline được
tự động triển khai khi code được merge vào các nhánh bảo vệ, cách cấu hình môi trường,
cách theo dõi lịch sử triển khai và cách rollback khi có sự cố.

Workflow liên quan: [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml) và
[`.github/workflows/rollback.yml`](.github/workflows/rollback.yml).

---

## 1. Tổng quan

- Merge vào nhánh **`develop`** → tự động triển khai môi trường **dev** (`--target dev`).
- Merge vào nhánh **`main`** → tự động triển khai môi trường **prod** (`--target prod`),
  kèm bước **backup trước khi deploy** và **health check sau deploy**.
- Pipeline chạy tuần tự: `dbt deps` → `dbt run` → `dbt snapshot` → `dbt test` → `dbt docs generate`.
- Nếu bất kỳ bước nào thất bại, quá trình triển khai dừng lại và team nhận thông báo lỗi.

---

## 2. Môi trường (Environments) và Secrets

Cấu hình kết nối SQL Server được truyền qua **biến môi trường**, do đó cùng một file
`dbt/profiles.yml` chạy được cả local (Docker) lẫn GitHub Actions mà không hardcode secret.
Xem thêm `.env.example`.

### 2.1. Hai target trong `profiles.yml`

| Target | Dùng cho | Kích hoạt |
|---|---|---|
| `dev` | Môi trường phát triển | Merge vào `develop`, hoặc `workflow_dispatch` chọn `dev` |
| `prod` | Môi trường production | Merge vào `main`, hoặc `workflow_dispatch` chọn `prod` |

Target được chọn qua biến môi trường `DBT_TARGET` (mặc định `dev`).

### 2.2. GitHub Environments

Vào **Settings → Environments** tạo 2 environment `dev` và `prod`. Mỗi environment chứa
**cùng tên secret** sau (giá trị khác nhau theo môi trường):

| Secret | Mô tả |
|---|---|
| `DBT_SQLSERVER_HOST` | Host của SQL Server |
| `DBT_SQLSERVER_DATABASE` | Tên database (mặc định `AdventureWorks2014`) |
| `DBT_SQLSERVER_USER` | Tài khoản SQL Server |
| `DBT_SQLSERVER_PASSWORD` | Mật khẩu SQL Server |
| `DBT_SCHEMA` | Schema đích của dbt (mặc định `dbo`) |

Secret ở cấp repository (dùng chung):

| Secret / Variable | Mô tả |
|---|---|
| `SLACK_WEBHOOK_URL` | Webhook Slack để gửi thông báo (không bắt buộc). |
| `DEPLOY_DB_MODE` (Variables) | Chế độ database cho sự kiện `push`: `container` (mặc định) hoặc `external`. |

> ⚠️ Không commit secret vào repository. `.env` đã nằm trong `.gitignore`.

---

## 3. Chế độ database (`db-mode`)

Workflow deploy hỗ trợ 2 chế độ:

| Chế độ | Mô tả | Khi nào dùng |
|---|---|---|
| `external` | Kết nối SQL Server **thật** qua secrets của GitHub Environment. | Triển khai thực tế với dev/prod thật. |
| `container` | Dựng SQL Server **dùng tạm** ngay trong runner, restore AdventureWorks2014, deploy rồi huỷ. | Demo CD không cần hạ tầng ngoài. |

- Sự kiện `push`: chế độ lấy từ biến `DEPLOY_DB_MODE` (mặc định `container`).
- Sự kiện `workflow_dispatch`: chọn `db-mode` trực tiếp trong form.

---

## 4. Quy trình triển khai (external mode)

Các job chạy tuần tự trong `deploy.yml`:

1. **determine-environment** — Xác định môi trường + target + db-mode dựa trên nhánh.
2. **pre-deploy** — Kiểm tra trước khi deploy: `dbt deps` → `dbt parse` → `dbt debug`
   (kiểm tra kết nối) → `dbt compile`.
3. **backup** (chỉ `prod`) — Chạy `BACKUP DATABASE` trước khi đụng vào dữ liệu production.
4. **deploy** — `dbt deps` → `dbt run` → `dbt snapshot` (nếu có thư mục `snapshots/`) → `dbt test`.
5. **post-deploy** — Health check (chạy lại `dbt test`), `dbt docs generate`, upload artifact
   (manifest/catalog/index.html + `dbt.log`) và ghi báo cáo triển khai vào job summary.
6. **notify** — Gửi thông báo kết quả qua Slack (nếu có `SLACK_WEBHOOK_URL`), nếu không thì
   ghi vào job summary kèm trạng thái thành công/thất bại.

> Chế độ `container` bỏ qua `pre-deploy`/`backup`/`post-deploy` và thực hiện
> `deps → debug → run → snapshot → test → docs generate` trên SQL Server tạm.

---

## 5. Rollback

Rollback chạy **thủ công** qua [`rollback.yml`](.github/workflows/rollback.yml) bằng
**Actions → Rollback → Run workflow**, với 3 tham số: `environment`, `ref`, `strategy`.

| Chiến lược | Cách hoạt động | Khi dùng |
|---|---|---|
| `state-aware` (mặc định) | Dùng `--defer --state` so với `manifest.json` của lần deploy thành công gần nhất, chỉ chạy lại các model **bị thay đổi**. | Rollback nhanh, ít rủi ro. |
| `full-redeploy` | Checkout về `ref` (tag/nhánh/commit) và chạy lại toàn bộ `dbt run --full-refresh` + `dbt test`. | Cần khôi phục nguyên trạng phiên bản cũ. |

**Quy trình rollback khuyến nghị:**
1. Xác định phiên bản ổn định (dùng tag, ví dụ `v1.0.0`, hoặc commit SHA).
2. Chạy workflow `Rollback` chọn environment cần quay lại.
3. Theo dõi job summary; nếu dùng `external`, dữ liệu prod còn có bản backup ở bước 3 mục 4.

---

## 6. Theo dõi lịch sử triển khai & tỷ lệ thành công

- **Lịch sử:** mở tab **Actions** → chọn workflow *Deploy* → xem từng lần chạy theo
  môi trường (`environment`) và kết quả (thành công/thất bại).
- **Báo cáo từng lần:** mỗi lần deploy ghi bảng tóm tắt (environment, target, branch,
  commit, người kích hoạt, link run) vào **job summary** của run.
- **Artifact:** `deploy-artifacts-<env>` chứa `manifest.json`, `catalog.json`,
  `index.html` (tài liệu) và `dbt.log` để truy vết.
- **Tỷ lệ thành công:** badge `Deploy` và `Rollback` trong `README.md` hiển thị trạng
  thái nhánh chính; kết hợp lịch sử Actions để thống kê theo tuần.

---

## 7. Xử lý sự cố thường gặp

| Triệu chứng | Nguyên nhân khả dĩ | Cách xử lý |
|---|---|---|
| Job `pre-deploy` fail ở `dbt debug` | Sai secret host/user/password hoặc SQL Server không mở port | Kiểm tra secrets trong Environment; xác minh kết nối thủ công bằng `dbt debug`. |
| Job `deploy` fail ở `dbt test` | Test chất lượng dữ liệu đỏ (dữ liệu sai lệch) | Xem log test, sửa model/nguồn rồi push lại. |
| Thông báo Slack không gửi | Thiếu `SLACK_WEBHOOK_URL` | Thêm secret repo hoặc chấp nhận fallback ghi vào job summary. |
| Rollback `state-aware` báo thiếu state | Không có artifact `deploy-artifacts-<env>` | Dùng chiến lược `full-redeploy` với ref ổn định. |
