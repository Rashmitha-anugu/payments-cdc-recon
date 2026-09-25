-- CDC-native SCD Type 2: every committed version of every account, in log order.
with versions as (
    select *
    from {{ ref('stg_cdc__accounts') }}
    -- at-least-once delivery can land the same change twice
    qualify row_number() over (
        partition by account_id, cdc_lsn
        order by file_name desc, file_row_number desc
    ) = 1
),

windowed as (
    select
        *,
        cdc_source_ts                                                         as valid_from,
        lead(cdc_source_ts) over (partition by account_id order by cdc_lsn)   as valid_to
    from versions
)

select
    md5(account_id::varchar || '|' || cdc_lsn::varchar)  as account_version_key,
    account_id,
    customer_name,
    email,
    country,
    tier,
    status,
    created_at,
    valid_from,
    valid_to,
    valid_to is null                                      as is_current,
    cdc_lsn
from windowed
where not is_deleted   -- a delete just closes the previous version's valid_to
