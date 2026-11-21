from datetime import datetime, timedelta
import os
import json
import logging
from urllib import request as urllib_request
from urllib.error import URLError

from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.models import Variable
from airflow.utils.email import send_email

log = logging.getLogger(__name__)

# ==============================================================================
# DAG DOCUMENTATION (Markdown render in Airflow UI)
# ==============================================================================
DAG_DOC_MD = """
# DataOps DBT Pipeline with Quality Gates
## Automated AdventureWorks Transformation & Quality Assurance

This pipeline orchestrates the end-to-end DBT transformation pipeline across three architectural layers:
- **Bronze Layer (Raw Ingestion)**: Views extracting from OLTP source schemas (`Sales`, `Production`, `Person`).
- **Silver Layer (Business Entities & Facts)**: Tables with cleaned, deduplicated, and business-logic enriched data.
- **Gold Layer (Analytics Marts)**: Aggregated analytical marts ready for reporting and dashboards.

### Quality Gate Strategy:
1. **Source Freshness Check**: Verifies that OLTP source data is not stale before running transformations.
2. **Bronze Quality Gate**: `dbt run --select tag:bronze` followed immediately by `dbt test --select tag:bronze`.
3. **Silver Quality Gate**: `dbt run --select tag:silver` followed by schema tests and custom generic tests.
4. **Gold Quality Gate**: `dbt run --select tag:gold` followed by analytical marts integrity tests.
5. **Reconciliation Test**: Singular test verifying financial reconciliation between Silver order lines and Gold monthly marts.
6. **Docs Generation**: Automatically refreshes DBT catalog and lineage documentation.

### Notification Channels (configure via Airflow UI > Admin > Variables & Connections):
- **Email**: Set `ALERT_EMAIL_TO` Variable (comma-separated) + configure `smtp_default` Connection.
- **Webhook** (Discord / Slack / Teams): Set `ALERT_WEBHOOK_URL` Variable with the full webhook URL.
- Both channels are **opt-in**: if not configured, the pipeline logs the alert and continues gracefully.

*Failure at any quality gate aborts the pipeline, preventing defective data from propagating.*
"""

# ==============================================================================
# DYNAMIC CONTAINER RESOLVER (No Hardcoded Container Names)
# ==============================================================================
DBT_CONTAINER_FILTER = Variable.get(
    "DBT_CONTAINER_NAME",
    default_var=os.getenv("DBT_CONTAINER_NAME", "dbt"),
)


def dbt_command(command: str) -> str:
    """
    Constructs a robust bash command executing dbt inside the active dbt container.
    Dynamically fetches container ID to avoid hardcoded docker-compose project names.
    """
    return (
        f'CONTAINER_ID=$(docker ps -qf "name={DBT_CONTAINER_FILTER}" | head -n 1); '
        f'if [ -z "$CONTAINER_ID" ]; then '
        f'  echo "ERROR: Active DBT container matching \'{DBT_CONTAINER_FILTER}\' not found!"; exit 1; '
        f'fi; '
        f'echo ">>> Executing: dbt {command} inside container: $CONTAINER_ID"; '
        f'docker exec $CONTAINER_ID dbt {command}'
    )


# ==============================================================================
# FAILURE NOTIFICATION CALLBACK
# Sends real notifications via Email (Airflow SMTP) and/or Webhook (Discord/Slack/Teams).
# Configure via Airflow UI > Admin > Variables:
#   - ALERT_EMAIL_TO       : "you@example.com,team@example.com"
#   - ALERT_WEBHOOK_URL    : "https://discord.com/api/webhooks/..." (or Slack / Teams URL)
# Configure SMTP via Airflow UI > Admin > Connections > smtp_default.
# ==============================================================================
def task_failure_alert(context):
    """
    Triggered when a task exhausts all retries and fails.
    Sends notifications to Email and/or Webhook based on configured Airflow Variables.
    Falls back to log-only if Variables are not set.
    """
    task_instance = context.get("task_instance")
    dag_id        = context.get("dag").dag_id
    task_id       = task_instance.task_id
    execution_date = context.get("execution_date")
    log_url       = task_instance.log_url
    exception     = context.get("exception")

    # ── Compose human-readable alert body ─────────────────────────────────────
    alert_text = (
        f"🚨 [DATAOPS PIPELINE FAILURE]\n"
        f"Pipeline   : {dag_id}\n"
        f"Failed Task: {task_id}\n"
        f"Run Date   : {execution_date}\n"
        f"Status     : FAILED (Retries Exhausted)\n"
        f"Exception  : {exception}\n"
        f"Log URL    : {log_url}\n"
        f"Action     : Review DBT test output and fix schema / data discrepancies."
    )

    log.error("=" * 80)
    log.error(alert_text)
    log.error("=" * 80)

    # ── Channel 1: Email via Airflow SMTP Connection (smtp_default) ───────────
    # Set Variable ALERT_EMAIL_TO = "addr1@example.com,addr2@example.com"
    # Set Connection smtp_default with your SMTP server credentials.
    try:
        email_to_raw = Variable.get("ALERT_EMAIL_TO", default_var="")
        if email_to_raw.strip():
            recipients = [e.strip() for e in email_to_raw.split(",") if e.strip()]
            html_body = f"""
            <h2>🚨 DataOps Pipeline Failure</h2>
            <table border="1" cellpadding="6" cellspacing="0">
              <tr><th>Pipeline</th><td>{dag_id}</td></tr>
              <tr><th>Failed Task</th><td><b>{task_id}</b></td></tr>
              <tr><th>Execution Date</th><td>{execution_date}</td></tr>
              <tr><th>Status</th><td style="color:red;"><b>FAILED (Retries Exhausted)</b></td></tr>
              <tr><th>Exception</th><td><code>{exception}</code></td></tr>
              <tr><th>Log URL</th><td><a href="{log_url}">{log_url}</a></td></tr>
            </table>
            <p><i>Action Required: Review DBT test logs and resolve schema or data discrepancies.</i></p>
            """
            send_email(
                to=recipients,
                subject=f"[AIRFLOW ALERT] {dag_id} — Task '{task_id}' FAILED",
                html_content=html_body,
            )
            log.info("✅ Failure alert email sent to: %s", recipients)
        else:
            log.info("ℹ️  ALERT_EMAIL_TO not configured — skipping email notification.")
    except Exception as email_err:
        log.warning("⚠️  Email notification failed (check smtp_default Connection): %s", email_err)

    # ── Channel 2: Webhook — Discord / Slack / Teams ───────────────────────────
    # Set Variable ALERT_WEBHOOK_URL with the full webhook URL.
    # Discord  : https://discord.com/api/webhooks/<id>/<token>
    # Slack    : https://hooks.slack.com/services/...
    # Teams    : https://outlook.office.com/webhook/...
    try:
        webhook_url = Variable.get("ALERT_WEBHOOK_URL", default_var="")
        if webhook_url.strip():
            # Discord uses {"content": "..."} ; Slack/Teams use {"text": "..."}
            # We send both keys so the same payload works for all three platforms.
            payload = json.dumps({
                "content": alert_text,          # Discord
                "text": alert_text,             # Slack / Teams
            }).encode("utf-8")

            req = urllib_request.Request(
                url=webhook_url.strip(),
                data=payload,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib_request.urlopen(req, timeout=10) as resp:
                log.info("✅ Webhook notification sent (HTTP %s).", resp.status)
        else:
            log.info("ℹ️  ALERT_WEBHOOK_URL not configured — skipping webhook notification.")
    except URLError as webhook_err:
        log.warning("⚠️  Webhook notification failed (check ALERT_WEBHOOK_URL Variable): %s", webhook_err)
    except Exception as webhook_err:
        log.warning("⚠️  Unexpected webhook error: %s", webhook_err)


# ==============================================================================
# DEFAULT ARGS & DAG DEFINITION
# ==============================================================================
default_args = {
    "owner": "dataops-team",
    "depends_on_past": False,
    "email_on_failure": False,   # Handled manually in task_failure_alert
    "email_on_retry": False,
    "retries": 3,
    "retry_delay": timedelta(minutes=5),
    "on_failure_callback": task_failure_alert,
}

with DAG(
    "dbt_transform_pipeline",
    default_args=default_args,
    description="Production DataOps DBT pipeline with Quality Gates and Automated Testing",
    doc_md=DAG_DOC_MD,
    schedule_interval="@daily",
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=["dataops", "dbt", "quality-gate", "adventureworks"],
) as dag:

    # 0. Install DBT dependencies
    dbt_deps = BashOperator(
        task_id="dbt_deps",
        bash_command=dbt_command("deps"),
        doc_md="Installs DBT packages declared in packages.yml (e.g. dbt_utils).",
    )

    # 1. Source freshness check
    dbt_freshness = BashOperator(
        task_id="dbt_source_freshness",
        bash_command=dbt_command("source freshness"),
        doc_md="Verifies freshness thresholds across all declared OLTP sources.",
    )

    # 2. Bronze layer — run then test (Quality Gate 1)
    dbt_run_bronze = BashOperator(
        task_id="dbt_run_bronze",
        bash_command=dbt_command("run --select tag:bronze"),
        doc_md="Materializes Bronze raw staging views from source tables.",
    )
    dbt_test_bronze = BashOperator(
        task_id="dbt_test_bronze",
        bash_command=dbt_command("test --select tag:bronze"),
        doc_md="Quality Gate 1: uniqueness, not_null, accepted_values on Bronze views.",
    )

    # 3. Silver layer — run then test (Quality Gate 2)
    dbt_run_silver = BashOperator(
        task_id="dbt_run_silver",
        bash_command=dbt_command("run --select tag:silver"),
        doc_md="Transforms Bronze views into cleaned Silver tables.",
    )
    dbt_test_silver = BashOperator(
        task_id="dbt_test_silver",
        bash_command=dbt_command("test --select tag:silver --exclude tag:gold --exclude test_type:singular"),
        doc_md="Quality Gate 2: FK relationships, custom generic tests (is_positive, no_future_dates, valid_date_range).",
    )

    # 4. Gold layer — run then test (Quality Gate 3)
    dbt_run_gold = BashOperator(
        task_id="dbt_run_gold",
        bash_command=dbt_command("run --select tag:gold"),
        doc_md="Materializes analytical Gold mart tables.",
    )
    dbt_test_gold = BashOperator(
        task_id="dbt_test_gold",
        bash_command=dbt_command("test --select tag:gold"),
        doc_md="Quality Gate 3: composite key uniqueness and metric integrity on Gold marts.",
    )

    # 5. Cross-layer reconciliation (singular test)
    dbt_test_reconciliation = BashOperator(
        task_id="dbt_test_reconciliation",
        bash_command=dbt_command("test --select test_type:singular"),
        doc_md="Reconciliation Gate: Silver net revenue must match Gold monthly summary (tolerance 1.0).",
    )

    # 6. Refresh documentation catalog
    dbt_docs = BashOperator(
        task_id="dbt_docs_generate",
        bash_command=dbt_command("docs generate"),
        doc_md="Generates updated DBT lineage catalog and documentation.",
    )

    # ── Pipeline dependency graph (strict linear Quality Gate chain) ──────────
    (
        dbt_deps
        >> dbt_freshness
        >> dbt_run_bronze
        >> dbt_test_bronze
        >> dbt_run_silver
        >> dbt_test_silver
        >> dbt_run_gold
        >> dbt_test_gold
        >> dbt_test_reconciliation
        >> dbt_docs
    )
