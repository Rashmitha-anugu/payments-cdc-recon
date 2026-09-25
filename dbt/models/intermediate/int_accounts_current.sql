-- Latest known state per account, ordered by LSN (not arrival time), deletes removed.
with ranked as (
    select
        *,
        row_number() over (
            partition by account_id
            order by cdc_lsn desc, file_name desc, file_row_number desc
        ) as rn
    from {{ ref('stg_cdc__accounts') }}
)

select account_id, customer_name, email, country, tier, status, created_at, updated_at, cdc_lsn
from ranked
where rn = 1
  and not is_deleted
