-- One row per change event (not per transaction). Current state is derived downstream.
select
    record:transaction_id::varchar              as transaction_id,
    record:account_id::number                   as account_id,
    record:amount::number(12, 2)                as amount,             -- Debezium sends decimals as strings
    upper(record:currency::varchar)             as currency,
    record:status::varchar                      as status,
    record:merchant_category::varchar           as merchant_category,
    {{ to_utc('record:created_at') }}           as created_at,
    {{ to_utc('record:updated_at') }}           as updated_at,
    record:__op::varchar                        as cdc_op,
    record:__lsn::number                        as cdc_lsn,
    {{ epoch_ms_to_utc('record:__source_ts_ms') }} as cdc_source_ts,
    coalesce(record:__deleted::boolean, false)  as is_deleted,
    file_name,
    file_row_number,
    loaded_at
from {{ source('raw', 'cdc_events') }}
where file_name like '%payments.public.transactions/%'
