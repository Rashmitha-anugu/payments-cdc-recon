select
    settlement_id,
    transaction_id,
    amount,
    upper(currency)          as currency,
    fee,
    {{ to_utc('settled_at') }} as settled_at,
    batch_date,
    file_name,
    loaded_at
from {{ source('raw', 'settlements') }}
