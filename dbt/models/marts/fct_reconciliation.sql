-- One row per transaction id seen on either side (ledger or processor), classified.

with ledger as (
    select transaction_id, account_id, amount, currency, status, transaction_date
    from {{ ref('fct_transactions') }}
    where not is_deleted
      and status <> 'pending'
),

settled as (
    select
        transaction_id,
        count(*)        as settlement_count,
        sum(amount)     as settled_amount,
        min(batch_date) as batch_date,
        min(currency)   as currency
    from {{ ref('stg_processor__settlements') }}
    group by transaction_id
),

joined as (
    select
        coalesce(l.transaction_id, s.transaction_id) as transaction_id,
        l.transaction_id is not null                 as in_ledger,
        l.account_id,
        l.status                                     as ledger_status,
        coalesce(l.currency, s.currency)             as currency,
        l.amount                                     as ledger_amount,
        s.settled_amount,
        coalesce(s.settlement_count, 0)              as settlement_count,
        l.transaction_date,
        s.batch_date
    from ledger as l
    full outer join settled as s
        on l.transaction_id = s.transaction_id
),

classified as (
    select
        *,
        case
            when not in_ledger                                  then 'ORPHAN_SETTLEMENT'
            when ledger_status = 'failed' and settlement_count > 0 then 'STATUS_MISMATCH'
            when ledger_status = 'failed'                       then 'NOT_SETTLEABLE'
            when settlement_count = 0
             and transaction_date > dateadd(day, -{{ var('settlement_lag_days') }}, {{ recon_as_of_date() }})
                                                                then 'AWAITING_SETTLEMENT'
            when settlement_count = 0                           then 'MISSING_SETTLEMENT'
            when settlement_count > 1                           then 'DUPLICATE_SETTLEMENT'
            when settled_amount <> ledger_amount                then 'AMOUNT_MISMATCH'
            else 'MATCHED'
        end as break_type
    from joined
)

select
    transaction_id::varchar                                   as transaction_id,
    account_id::number                                        as account_id,
    ledger_status::varchar                                    as ledger_status,
    currency::varchar                                         as currency,
    ledger_amount::number(12, 2)                              as ledger_amount,
    settled_amount::number(12, 2)                             as settled_amount,
    settlement_count::number                                  as settlement_count,
    transaction_date::date                                    as transaction_date,
    batch_date::date                                          as batch_date,
    coalesce(transaction_date, batch_date)::date              as business_date,
    break_type::varchar                                       as break_type,
    (break_type not in ('MATCHED', 'AWAITING_SETTLEMENT'))::boolean as is_break,
    (case break_type
        when 'MISSING_SETTLEMENT'   then ledger_amount
        when 'AMOUNT_MISMATCH'      then abs(settled_amount - ledger_amount)
        when 'DUPLICATE_SETTLEMENT' then settled_amount - ledger_amount
        when 'ORPHAN_SETTLEMENT'    then settled_amount
        when 'STATUS_MISMATCH'      then settled_amount
        else 0
    end)::number(12, 2)                                       as amount_at_risk
from classified
where break_type <> 'NOT_SETTLEABLE'
