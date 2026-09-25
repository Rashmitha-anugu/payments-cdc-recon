select
    business_date,
    count(*)                                             as transactions,
    count_if(break_type = 'MATCHED')                     as matched,
    count_if(break_type = 'AWAITING_SETTLEMENT')         as awaiting_settlement,
    count_if(is_break)                                   as breaks,
    count_if(break_type = 'MISSING_SETTLEMENT')          as missing_settlement,
    count_if(break_type = 'AMOUNT_MISMATCH')             as amount_mismatch,
    count_if(break_type = 'DUPLICATE_SETTLEMENT')        as duplicate_settlement,
    count_if(break_type = 'ORPHAN_SETTLEMENT')           as orphan_settlement,
    count_if(break_type = 'STATUS_MISMATCH')             as status_mismatch,
    div0(count_if(is_break), count_if(break_type <> 'AWAITING_SETTLEMENT')) as break_rate,
    sum(amount_at_risk)                                  as amount_at_risk
from {{ ref('fct_reconciliation') }}
group by business_date
