FROM apache/airflow:3.3.2-python3.12

ARG AIRFLOW_VERSION=3.3.2
ARG CONSTRAINTS=https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-3.12.txt

RUN pip install --no-cache-dir "apache-airflow==${AIRFLOW_VERSION}" \
      apache-airflow-providers-snowflake apache-airflow-providers-common-sql \
      "psycopg[binary]" boto3 \
      --constraint "${CONSTRAINTS}"

# dbt gets its own virtualenv so its dependencies never fight Airflow's.
RUN python -m venv /home/airflow/dbt-venv \
 && /home/airflow/dbt-venv/bin/pip install --no-cache-dir dbt-core==1.12.5 dbt-snowflake==1.12.1
