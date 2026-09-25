"""Daily ledger-vs-processor reconciliation.

CDC data streams in continuously (Debezium -> Kafka -> S3 -> Snowpipe); this DAG handles
the daily batch side: wait for the processor file, rebuild the models, and alert on breaks.
"""

from __future__ import annotations

import json
from datetime import datetime, timedelta

from airflow.exceptions import AirflowFailException
from airflow.providers.common.sql.sensors.sql import SqlSensor
from airflow.providers.snowflake.hooks.snowflake import SnowflakeHook
from airflow.providers.standard.operators.bash import BashOperator
from airflow.sdk import dag, get_current_context, task

DBT = "cd /opt/airflow/dbt && /home/airflow/dbt-venv/bin/dbt"
DBT_FLAGS = "--profiles-dir . --target prod"
BREAK_RATE_THRESHOLD = 0.05  # generator's default injection rates land around 3%

# Airflow 3 cron schedules run *at* the trigger time, so {{ ds }} is today.
# The processor file we reconcile covers yesterday.
BATCH_DATE = "{{ macros.ds_add(ds, -1) }}"


@dag(
    schedule="0 6 * * *",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    max_active_runs=1,
    default_args={"retries": 2, "retry_delay": timedelta(minutes=5)},
    tags=["payments", "reconciliation"],
)
def payments_reconciliation_daily():
    # In real life the processor drops this file. Here we simulate it so the demo is self-contained.
    simulate_processor_file = BashOperator(
        task_id="simulate_processor_settlement_file",
        bash_command=f"python /opt/airflow/generator/settlements.py --date {BATCH_DATE}",
    )

    wait_for_settlements = SqlSensor(
        task_id="wait_for_settlements_in_snowflake",
        conn_id="snowflake_default",
        sql=f"select count(*) from PAYMENTS.RAW.SETTLEMENTS where batch_date = '{BATCH_DATE}'",
        poke_interval=60,
        timeout=60 * 60,
        mode="reschedule",
    )

    source_freshness = BashOperator(
        task_id="dbt_source_freshness",
        bash_command=f"{DBT} source freshness {DBT_FLAGS}",
    )

    dbt_build = BashOperator(
        task_id="dbt_build",
        bash_command=(
            f"{DBT} build {DBT_FLAGS} "
            "--vars '{\"recon_as_of_date\": \"{{ ds }}\"}'"
        ),
    )

    @task
    def check_break_rate() -> dict:
        ctx = get_current_context()
        batch_date = ctx["macros"].ds_add(ctx["ds"], -1)
        row = SnowflakeHook(snowflake_conn_id="snowflake_default").get_first(
            """select transactions, breaks, break_rate, amount_at_risk
               from PAYMENTS.MARTS.RPT_RECONCILIATION_DAILY
               where business_date = %(d)s""",
            parameters={"d": batch_date},
        )
        if row is None:
            raise AirflowFailException(f"No reconciliation row for {batch_date}")

        result = dict(zip(["transactions", "breaks", "break_rate", "amount_at_risk"], row, strict=True))
        print(json.dumps({"batch_date": batch_date, **result}, default=str))

        if float(result["break_rate"]) > BREAK_RATE_THRESHOLD:
            # Swap for a Slack/PagerDuty notifier in a real deployment.
            raise AirflowFailException(
                f"Break rate {float(result['break_rate']):.2%} exceeds {BREAK_RATE_THRESHOLD:.0%} for {batch_date}; "
                f"amount at risk {result['amount_at_risk']}"
            )
        return result

    simulate_processor_file >> wait_for_settlements >> source_freshness >> dbt_build >> check_break_rate()


payments_reconciliation_daily()
