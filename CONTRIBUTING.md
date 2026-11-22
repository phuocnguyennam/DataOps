# CONTRIBUTING.md — Hướng dẫn đóng góp

Tài liệu này mô tả cách làm việc với repository: mô hình nhánh, quy ước commit, quy trình
mở Pull Request và các kiểm tra chất lượng tự động (CI) áp dụng trước khi code được merge.

Workflow liên quan: [`.github/workflows/ci.yml`](.github/workflows/ci.yml).

---

## 1. Mô hình nhánh (Branching model)

| Nhánh | Mục đích | Môi trường deploy |
|---|---|---|
| `main` | Production — chỉ chứa code đã kiểm duyệt | `prod` |
| `develop` | Tích hợp chung của team | `dev` |
| `feature/*` | Một tính năng / sửa lỗi (từ `develop`) | — |

Luồng làm việc:

```
feature/<tên>  ──(Pull Request)──►  develop  ──(merge)──►  main
```

- Luôn tạo nhánh mới từ `develop` cho mọi thay đổi.
- Không commit trực tiếp vào `main` hoặc `develop`.
- Mọi thay đổi vào `develop`/`main` đều qua Pull Request.

---

## 2. Quy ước commit (Conventional Commits)

Mọi commit phải tuân theo định dạng:

```
<type>(<scope>)?!?: <mô tả>
```

Các `type` hợp lệ: `build`, `chore`, `ci`, `docs`, `feat`, `fix`, `perf`, `refactor`,
`revert`, `style`, `test`.

Ví dụ:

```text
feat(models): thêm gld_customer_metrics
fix(dag): sửa thứ tự task trong dbt_dag.py
ci: thêm bước sqlfluff vào workflow
docs: cập nhật DEPLOYMENT.md
```

> CI sẽ tự động **từ chối** PR có tiêu đề không đúng định dạng này.

---

## 3. Quy trình đóng góp

1. Đồng bộ nhánh mới nhất:
   ```bash
   git checkout develop
   git pull origin develop
   ```
2. Tạo nhánh tính năng:
   ```bash
   git checkout -b feature/<tên-ngắn-gọn>
   ```
3. Thực hiện thay đổi và commit theo quy ước ở mục 2.
4. Push và mở Pull Request vào `develop` (hoặc `main` nếu là hotfix).
5. Chờ CI chạy xanh (xem mục 4), nhờ ít nhất 1 thành viên review.
6. Sau khi được approve và CI pass, merge PR.

---

## 4. Kiểm tra tự động (CI)

Khi mở PR, [`ci.yml`](.github/workflows/ci.yml) tự chạy:

| Kiểm tra | Nội dung |
|---|---|
| **PR validation** | Tiêu đề đúng Conventional Commits; file thay đổi < 1 MB; không có conflict. |
| **Python quality** | `flake8` + `black --check` trên thư mục `airflow/` (line-length 88, cấu hình trong `setup.cfg`). |
| **SQL lint** | `sqlfluff` trên `dbt/models` (cấu hình trong `.sqlfluff`). |
| **DBT build** | `dbt deps` → `dbt parse` → `dbt build` → `dbt docs generate` trên SQL Server dùng tạm. |

Chạy cục bộ trước khi push để tránh CI đỏ:

```bash
# Python
flake8 airflow/ --count --show-source --statistics
black --check airflow/

# SQL
sqlfluff lint --config .sqlfluff dbt/models

# DBT (cần SQL Server đang chạy)
cd dbt
dbt deps
dbt build
```

---

## 5. Quy ước chất lượng code

- **SQL (dbt):** đặt tên model theo layer `brnz_` / `slvr_` / `gld_`; document cột và
  gắn test (`not_null`, `unique`, `relationships`, `accepted_values`) trong file
  `_*__models.yml`.
- **Python (Airflow):** tuân thủ `flake8`/`black` (dòng tối đa 88 ký tự).
- **Bảo mật:** không commit secret; dùng biến môi trường (tham khảo `.env.example`).
- **Tài liệu:** cập nhật README/DEPLOYMENT.md khi thay đổi hành vi pipeline.

---

## 6. Review checklist

Trước khi approve PR, xác nhận:

- [ ] Tiêu đề PR đúng Conventional Commits.
- [ ] Các job CI đều xanh.
- [ ] Model mới có schema.yml (mô tả + test).
- [ ] Không thay đổi `docker-compose.yml`/`profiles.yml` ngoài dự kiến.
- [ ] Không commit secret hoặc file tạm (`.env`, `target/`, log).
