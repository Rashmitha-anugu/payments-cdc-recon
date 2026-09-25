{{
  config(
    materialized='incremental',
    unique_key='transaction_id',
    incremental_strategy='merge',
    on_schema_change='append_new_columns'
  )
}}

-- Current state per transaction, merged incrementally from CDC events.
-- Deletes are kept as soft deletes (is_deleted) because MERGE can't remove rows here.

with changes as (
    select *
    from {{ ref('stg_cdc__transactions') }}
    {% if is_incremental() %}
    -- 1h lookback: Snowpipe loads files in parallel, so loaded_at is not strictly ordered.
    -- Re-reading is safe because of the LSN guard below.
    where loaded_at > (select dateadd(hour, -1, max(_loaded_at)) from {{ this }})
    {% endif %}
),

latest as (
    select *
    from changes
    qualify row_number() over (
        partition by transaction_id
        order by cdc_lsn desc, file_name desc, file_row_number desc
    ) = 1
)

select
    l.transaction_id,
    l.account_id,
    l.amount,
    l.currency,
    l.status,
    l.merchant_category,
    l.created_at,
    l.created_at::date as transaction_date,
    l.updated_at,
    l.is_deleted,
    l.cdc_lsn,
    l.loaded_at        as _loaded_at
from latest as l
{% if is_incremental() %}
left join {{ this }} as t
    on t.transaction_id = l.transaction_id
-- Never let an older change overwrite a newer one (late or replayed files).
where t.transaction_id is null
   or l.cdc_lsn > t.cdc_lsn
{% endif %}
