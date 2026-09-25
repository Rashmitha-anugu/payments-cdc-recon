select account_id, count(*) as current_versions
from {{ ref('dim_accounts') }}
where is_current
group by account_id
having count(*) > 1
