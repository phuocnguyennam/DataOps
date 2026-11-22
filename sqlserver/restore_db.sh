#!/bin/bash
# Khôi phục AdventureWorks2014 vào SQL Server khi container khởi động.
# Chạy nền (background) song song với sqlservr.
# Idempotent: nếu DB đã tồn tại thì bỏ qua restore, chỉ đảm bảo login dbt tồn tại.

set -euo pipefail

SA_PASSWORD="${SA_PASSWORD:-YourStrong@Passw0rd}"
BAK="/tmp/AdventureWorks2014.bak"
BAK_URL="https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorks2014.bak"
SQLCMD="/opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P ${SA_PASSWORD}"

echo "[restore_db] Chờ SQL Server sẵn sàng..."
ready=0
for i in $(seq 1 90); do
    if $SQLCMD -Q "SELECT 1" >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 2
done
if [ "$ready" -ne 1 ]; then
    echo "[restore_db] SQL Server không sẵn sàng sau 3 phút, bỏ qua."
    exit 0
fi

# 1) Restore nếu DB chưa tồn tại
if $SQLCMD -Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE name = 'AdventureWorks2014'" -h -1 | grep -q AdventureWorks2014; then
    echo "[restore_db] AdventureWorks2014 đã tồn tại, bỏ qua restore."
else
    if [ ! -f "$BAK" ]; then
        echo "[restore_db] Tải AdventureWorks2014.bak ..."
        curl -fL --retry 3 -o "$BAK" "$BAK_URL"
    fi
    echo "[restore_db] Đang restore AdventureWorks2014 ..."
    $SQLCMD -Q "RESTORE DATABASE AdventureWorks2014 FROM DISK = '$BAK' WITH MOVE 'AdventureWorks2014_Data' TO '/var/opt/mssql/data/AdventureWorks2014.mdf', MOVE 'AdventureWorks2014_Log' TO '/var/opt/mssql/data/AdventureWorks2014_log.ldf'"
    echo "[restore_db] Restore xong."
fi

# 2) Đảm bảo login `imrandbtnew` (dùng cho dbt) tồn tại
echo "[restore_db] Đảm bảo login imrandbtnew tồn tại..."
$SQLCMD -Q "IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'imrandbtnew') CREATE LOGIN imrandbtnew WITH PASSWORD = 'Imran@12345'"
$SQLCMD -d AdventureWorks2014 -Q "IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'imrandbtnew') CREATE USER imrandbtnew FOR LOGIN imrandbtnew; ALTER ROLE db_owner ADD MEMBER imrandbtnew;"

echo "[restore_db] Hoàn tất."
