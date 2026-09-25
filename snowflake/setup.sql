-- RAW landing layer: stages, tables and auto-ingest pipes.
-- Rendered by `make snowflake-setup` (envsubst fills ${S3_BUCKET}); safe to re-run.

use role PAYMENTS_TRANSFORMER;
use warehouse PAYMENTS_WH;
use database PAYMENTS;

create schema if not exists RAW;
use schema RAW;

create file format if not exists ff_ndjson
    type = json;

create file format if not exists ff_settlement_csv
    type = csv
    skip_header = 1
    field_optionally_enclosed_by = '"'
    null_if = ('')
    error_on_column_count_mismatch = true;

create stage if not exists stg_cdc
    url = 's3://${S3_BUCKET}/cdc/'
    storage_integration = PAYMENTS_S3_INT
    file_format = ff_ndjson;

create stage if not exists stg_settlements
    url = 's3://${S3_BUCKET}/settlements/'
    storage_integration = PAYMENTS_S3_INT
    file_format = ff_settlement_csv;

-- One table for every CDC topic: schema-on-read keeps upstream column adds from breaking ingestion.
-- dbt staging models split it by topic (derived from file_name) and type the fields.
create table if not exists cdc_events (
    record          variant,
    file_name       varchar,
    file_row_number number,
    loaded_at       timestamp_ltz default current_timestamp()
);

create table if not exists settlements (
    settlement_id  varchar,
    transaction_id varchar,
    amount         number(12, 2),
    currency       varchar,
    fee            number(12, 2),
    settled_at     timestamp_tz,
    batch_date     date,
    file_name      varchar,
    loaded_at      timestamp_ltz default current_timestamp()
);

create pipe if not exists pipe_cdc auto_ingest = true as
    copy into cdc_events (record, file_name, file_row_number)
    from (select $1, metadata$filename, metadata$file_row_number from @stg_cdc);

create pipe if not exists pipe_settlements auto_ingest = true as
    copy into settlements (settlement_id, transaction_id, amount, currency, fee, settled_at, batch_date, file_name)
    from (select $1, $2, $3, $4, $5, $6, $7, metadata$filename from @stg_settlements);

-- Copy notification_channel into terraform.tfvars as snowpipe_sqs_arn, then `terraform apply` again.
show pipes in schema RAW;

-- Files that landed before notifications were wired aren't picked up automatically:
-- alter pipe pipe_cdc refresh;
-- alter pipe pipe_settlements refresh;
