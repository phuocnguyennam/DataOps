FROM mcr.microsoft.com/mssql/server:2019-latest

# Install curl and mssql-tools
USER root
RUN apt-get update && apt-get install -y curl gnupg2

# Install mssql-tools
RUN curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add - && \
    curl https://packages.microsoft.com/config/ubuntu/20.04/prod.list > /etc/apt/sources.list.d/mssql-release.list && \
    apt-get update && \
    ACCEPT_EULA=Y apt-get install -y mssql-tools unixodbc-dev && \
    echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc

# Script khôi phục AdventureWorks2014 (tự tải backup + restore + tạo login dbt)
COPY restore_db.sh /tmp/restore_db.sh
RUN chmod +x /tmp/restore_db.sh

# Switch back to mssql user
USER mssql

# Chạy restore_db.sh nền rồi khởi động SQL Server
CMD /bin/sh -c "/tmp/restore_db.sh & exec /opt/mssql/bin/sqlservr"
