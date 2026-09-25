-- One row per change event (not per account). Current state is derived downstream.
select
    record:account_id::number                   as account_id,
    record:customer_name::varchar               as customer_name,
    record:email::varchar                       as email,
    record:country::varchar                     as country,
    record:tier::varchar                        as tier,
    record:status::varchar                      as status,
    {{ to_utc('record:created_at') }}           as created_at,
    {{ to_utc('record:updated_at') }}           as updated_at,
    record:__op::varchar                        as cdc_op,          -- r=snapshot c=insert u=update d=delete
    record:__lsn::number                        as cdc_lsn,         -- Postgres log position: the true ordering key
    {{ epoch_ms_to_utc('record:__source_ts_ms') }} as cdc_source_ts,
    coalesce(record:__deleted::boolean, false)  as is_deleted,
    file_name,
    file_row_number,
    loaded_at
from {{ source('raw', 'cdc_events') }}
where file_name like '%payments.public.accounts/%'
