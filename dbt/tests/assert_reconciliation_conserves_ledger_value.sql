-- Every settleable ledger dollar must appear in the reconciliation exactly once.
-- Catches fan-out from bad joins, which a row-count test would miss.
with ledger as (
    select coalesce(sum(amount), 0) as total
    from {{ ref('fct_transactions') }}
    where not is_deleted and status in ('succeeded', 'refunded')
),

recon as (
    select coalesce(sum(ledger_amount), 0) as total
    from {{ ref('fct_reconciliation') }}
    where ledger_status in ('succeeded', 'refunded')
)

select ledger.total as ledger_total, recon.total as recon_total
from ledger cross join recon
where ledger.total <> recon.total
