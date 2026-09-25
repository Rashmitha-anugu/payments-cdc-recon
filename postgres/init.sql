-- Source OLTP schema for a simulated payments app.

create table accounts (
    account_id     bigserial primary key,
    customer_name  text not null,
    email          text not null,
    country        text not null,
    tier           text not null default 'standard' check (tier in ('standard', 'plus', 'business')),
    status         text not null default 'active'   check (status in ('active', 'frozen', 'closed')),
    created_at     timestamptz not null default now(),
    updated_at     timestamptz not null default now()
);

create table transactions (
    transaction_id    uuid primary key default gen_random_uuid(),
    account_id        bigint not null references accounts (account_id),
    amount            numeric(12, 2) not null check (amount > 0),
    currency          text not null,
    status            text not null check (status in ('pending', 'succeeded', 'failed', 'refunded')),
    merchant_category text not null,
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now()
);

create index on transactions (created_at);
create index on transactions (status);

-- Keep updated_at honest no matter who writes to the table.
create or replace function set_updated_at() returns trigger as $$
begin
    new.updated_at := now();
    return new;
end;
$$ language plpgsql;

create trigger accounts_updated_at     before update on accounts     for each row execute function set_updated_at();
create trigger transactions_updated_at before update on transactions for each row execute function set_updated_at();

-- FULL replica identity: delete events carry the whole "before" row, not just the PK.
alter table accounts     replica identity full;
alter table transactions replica identity full;
