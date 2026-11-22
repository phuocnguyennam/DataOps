# DBT + Airflow DataOps Pipeline

Link GitHub: https://github.com/phuocnguyennam/DataOps

Pipeline dữ liệu tự động: trích xuất dữ liệu từ **SQL Server (AdventureWorks2014)**,
biến đổi theo kiến trúc **medallion (bronze → silver → gold)** bằng **DBT**, điều phối
bằng **Apache Airflow**, và triển khai tự động qua **GitHub Actions (CI/CD)**.

---

## 1. Tổng quan

Dự án hiện thực một pipeline DataOps hoàn chỉnh theo mô hình **Medallion Architecture**:

- **Bronze (view):** nạp thô từ 5 bảng nguồn OLTP, chuẩn hóa tên cột (snake_case), ép kiểu,
  loại bỏ cột kỹ thuật/nhạy cảm.
- **Silver (table):** làm sạch và làm giàu nghiệp vụ — giải mã mã code, phân khúc khách hàng,
  tính toán doanh thu/chi phí/lợi nhuận.
- **Gold (table):** các mart phục vụ phân tích — KPI theo ngày/tháng, hiệu suất sản phẩm,
  giá trị vòng đời khách hàng (LTV) và tăng trưởng MoM.

Chất lượng dữ liệu được đảm bảo bằng các **test tự động** (schema test + custom test + freshness),
chạy như **quality gate** giữa các tầng trong Airflow.

## 2. Kiến trúc hệ thống

```
┌──────────────┐     ┌───────────────────┐     ┌───────────────────┐
│  SQL Server  │────▶│       DBT         │────▶│    SQL Server     │
│  (nguồn OLTP)│     │ bronze→silver→gold│     │ (mart phân tích)  │
└──────────────┘     └───────────────────┘     └───────────────────┘
         ▲                    ▲                          ▲
         │            ┌───────┴────────┐                 │
         │            │    Airflow     │                 │
         │            │ (điều phối DAG)│                 │
         │            └───────┬────────┘                 │
         │                    │ metadata                 │
         │              ┌─────▼─────┐   ┌──────────┐    │
         └──────────────│ PostgreSQL │   │GitHub    │────┘
                        └───────────┘   │Actions CI│
                                        └──────────┘
```

**Luồng dữ liệu:** SQL Server (nguồn) → DBT (bronze → silver → gold) → SQL Server (mart).
**Điều phối:** Airflow Scheduler chạy DAG theo lịch, gọi `docker exec` vào DBT container.
**CI/CD:** GitHub Actions kiểm tra khi mở PR và tự động triển khai khi merge vào `develop`/`main`.

> Sơ đồ chi tiết (PlantUML): [`docs/diagrams/`](docs/diagrams/README.md)
> — kiến trúc, data lineage, quy trình CI/CD và luồng Airflow DAG.

## 3. Công nghệ sử dụng

| Thành phần | Công nghệ |
|---|---|
| Điều phối | Apache Airflow (Docker) |
| Biến đổi | DBT (dbt-sqlserver + dbt_utils) |
| Cơ sở dữ liệu | SQL Server 2019 + AdventureWorks2014 |
| Container | Docker & Docker Compose |
| CI/CD | GitHub Actions |
| Chất lượng code | flake8, black (Python) · sqlfluff (SQL) |

## 4. Cấu trúc repository

```
.
├── .github/workflows/        # ci.yml, deploy.yml, rollback.yml
├── airflow/
│   ├── dags/dbt_dag.py       # DAG dbt_transform_pipeline (quality gate)
│   └── Dockerfile
├── dbt/
│   ├── models/
│   │   ├── bronze/           # 5 model thô + _sources.yml + _bronze__models.yml
│   │   ├── silver/           # 4 model nghiệp vụ + _silver__models.yml
│   │   └── gold/             # 4 mart phân tích + _gold__models.yml
│   ├── tests/                # generic (3) + singular (1)
│   ├── dbt_project.yml       # cấu hình project + tags theo tầng
│   ├── packages.yml          # dbt_utils
│   └── profiles.yml          # target dev/prod (qua biến môi trường)
├── sqlserver/                # Dockerfile + restore AdventureWorks2014
├── docs/diagrams/            # sơ đồ PlantUML
├── docker-compose.yml
├── .env.example              # mẫu biến môi trường
├── README.md                 # file này
├── MODELS.md                 # catalog mô hình dữ liệu
├── DEPLOYMENT.md             # runbook triển khai + rollback
└── CONTRIBUTING.md           # hướng dẫn đóng góp
```

## 5. Các tầng dữ liệu

| Tầng | Materialization | Số model | Vai trò |
|---|---|---|---|
| Bronze | view | 5 | Nạp thô + chuẩn hóa |
| Silver | table | 4 | Làm sạch + logic nghiệp vụ |
| Gold | table | 4 | Mart phân tích sẵn sàng cho BI |

Chi tiết từng model, cột và test: xem **[MODELS.md](MODELS.md)**.

## 6. Thiết lập nhanh (Quick Start)

### Yêu cầu tiên quyết
- Docker Desktop (Windows 10/11, backend WSL2) + Docker Compose
- Git

### Bước 1 — Khởi động dịch vụ
```powershell
docker-compose up -d --build
```

Các dịch vụ:
| Dịch vụ | Cổng | Mô tả |
|---|---|---|
| `sqlserver` | 1433 | SQL Server nguồn (AdventureWorks2014) |
| `postgres` | 5432 | Metadata của Airflow |
| `airflow-webserver` | 8080 | Giao diện Airflow (admin / admin) |
| `airflow-scheduler` | — | Lập lịch chạy DAG |
| `dbt` | — | Container chạy lệnh DBT |

### Bước 2 — Chạy DBT
```powershell
docker-compose exec dbt dbt deps
docker-compose exec dbt dbt run
docker-compose exec dbt dbt test
docker-compose exec dbt dbt docs generate
```

### Bước 3 — Truy cập Airflow
Mở <http://localhost:8080> (tài khoản `admin` / `admin`), bật DAG `dbt_transform_pipeline`
để chạy pipeline tự động theo lịch `@daily`.

> Hướng dẫn cài đặt chi tiết từ máy mới: **[0. NEW_COMPUTER_SETUP.md](0.%20NEW_COMPUTER_SETUP.md)**.

## 7. Testing (chất lượng dữ liệu)

- **Schema tests:** `not_null`, `unique`, `relationships`, `accepted_values`, `unique_combination_of_columns`.
- **Custom generic tests:** `is_positive`, `no_future_dates`, `valid_date_range`.
- **Singular test:** đối soát doanh thu giữa Silver và Gold.
- **Source freshness:** cấu hình `warn_after` cho mọi nguồn.

Chạy toàn bộ test: `dbt test`.

## 8. Airflow Orchestration

DAG `dbt_transform_pipeline` chạy chuỗi **quality gate**:

```
dbt_deps → source_freshness → run/test bronze → run/test silver
         → run/test gold → reconciliation → docs generate
```

- `retries = 3`, `retry_delay = 5 phút`, lịch `@daily`.
- Thông báo lỗi qua **email + webhook (Slack/Discord/Teams)** khi task thất bại.
- Không hardcode tên container — tìm container DBT động qua Airflow Variable `DBT_CONTAINER_NAME`.

## 9. CI/CD

| Workflow | Kích hoạt | Chức năng |
|---|---|---|
| `ci.yml` | Pull request | PR validation, flake8/black, sqlfluff, `dbt build` + docs |
| `deploy.yml` | Push vào `develop`/`main` | Tự động `dbt deps → run → test`, phân biệt dev/prod, backup + health check + thông báo |
| `rollback.yml` | Thủ công | Rollback theo state-aware hoặc full-redeploy |

Chi tiết quy trình triển khai, môi trường và rollback: **[DEPLOYMENT.md](DEPLOYMENT.md)**.

## 10. Tài liệu

| Tài liệu | Nội dung |
|---|---|
| [MODELS.md](MODELS.md) | Catalog mô hình dữ liệu (bronze/silver/gold + tests) |
| [DEPLOYMENT.md](DEPLOYMENT.md) | Runbook triển khai, rollback, theo dõi lịch sử |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Mô hình nhánh, quy ước commit, quy trình PR |
| [docs/diagrams/](docs/diagrams/README.md) | Sơ đồ PlantUML (kiến trúc, lineage, CI/CD, DAG) |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Xử lý sự cố thường gặp |
| [docker_commands.md](docker_commands.md) | Bảng lệnh Docker hay dùng |

## 11. Troubleshooting

Các lỗi thường gặp khi chạy Docker/DBT/Airflow: xem **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)**.

## 12. Đóng góp

Quy tắc nhánh, commit và Pull Request: xem **[CONTRIBUTING.md](CONTRIBUTING.md)**.
