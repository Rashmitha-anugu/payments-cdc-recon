"""Simulated payments-app traffic against Postgres (the CDC source).

python generator/traffic.py --backfill-days 7   # history, so there is something to reconcile
python generator/traffic.py --rate 5            # live inserts/updates/deletes, ~5 ops/sec
"""

from __future__ import annotations

import argparse
import os
import random
import time
from datetime import UTC, datetime, timedelta
from decimal import Decimal

import psycopg
from faker import Faker

CATEGORIES = ["grocery", "travel", "electronics", "restaurants", "fuel", "software", "apparel"]
CURRENCIES = ["USD"] * 8 + ["EUR", "GBP"]
TIERS = ["standard", "standard", "standard", "plus", "business"]


def rand_amount(rng: random.Random) -> Decimal:
    value = min(max(rng.lognormvariate(3.2, 1.0), 0.5), 5000)
    return Decimal(str(round(value, 2)))


def create_account(cur, fake: Faker, rng: random.Random, ts: datetime | None = None) -> int:
    ts = ts or datetime.now(UTC)
    cur.execute(
        """insert into accounts (customer_name, email, country, tier, created_at, updated_at)
           values (%s, %s, %s, %s, %s, %s) returning account_id""",
        (fake.name(), fake.email(), fake.country_code(), rng.choice(TIERS), ts, ts),
    )
    return cur.fetchone()[0]


def active_account_ids(cur) -> list[int]:
    cur.execute("select account_id from accounts where status = 'active'")
    return [r[0] for r in cur.fetchall()]


def backfill(conn, days: int, per_day: int, rng: random.Random, fake: Faker) -> None:
    today = datetime.now(UTC).replace(hour=0, minute=0, second=0, microsecond=0)
    with conn.cursor() as cur:
        start = today - timedelta(days=days)
        for _ in range(50):
            create_account(cur, fake, rng, start)
        accounts = active_account_ids(cur)

        for d in range(days, 0, -1):
            day = today - timedelta(days=d)
            for _ in range(per_day):
                created = day + timedelta(seconds=rng.randint(0, 86_399))
                status = rng.choices(["succeeded", "failed", "refunded"], [0.90, 0.07, 0.03])[0]
                cur.execute(
                    """insert into transactions
                         (account_id, amount, currency, status, merchant_category, created_at, updated_at)
                       values (%s, %s, %s, %s, %s, %s, %s)""",
                    (
                        rng.choice(accounts),
                        rand_amount(rng),
                        rng.choice(CURRENCIES),
                        status,
                        rng.choice(CATEGORIES),
                        created,
                        created + timedelta(seconds=rng.randint(1, 600)),
                    ),
                )
            conn.commit()
            print(f"backfilled {per_day} transactions for {day.date()}")


# --- live mode: each action is one small OLTP-style statement -----------------


def new_transaction(cur, fake, rng):
    accounts = active_account_ids(cur) or [create_account(cur, fake, rng)]
    cur.execute(
        """insert into transactions (account_id, amount, currency, status, merchant_category)
           values (%s, %s, %s, 'pending', %s)""",
        (rng.choice(accounts), rand_amount(rng), rng.choice(CURRENCIES), rng.choice(CATEGORIES)),
    )


def resolve_pending(cur, fake, rng):
    outcome = rng.choices(["succeeded", "failed"], [0.93, 0.07])[0]
    cur.execute(
        """update transactions set status = %s
           where transaction_id = (select transaction_id from transactions
                                   where status = 'pending' order by created_at limit 1
                                   for update skip locked)""",
        (outcome,),
    )


def refund(cur, fake, rng):
    cur.execute(
        """update transactions set status = 'refunded'
           where transaction_id = (select transaction_id from transactions
                                   where status = 'succeeded' order by random() limit 1)"""
    )


def update_account(cur, fake, rng):
    change = rng.choice(["tier", "status", "email"])
    if change == "tier":
        cur.execute(
            "update accounts set tier = %s where account_id = "
            "(select account_id from accounts order by random() limit 1)",
            (rng.choice(TIERS),),
        )
    elif change == "status":
        cur.execute(
            "update accounts set status = %s where account_id = "
            "(select account_id from accounts order by random() limit 1)",
            (rng.choice(["active", "active", "frozen", "closed"]),),
        )
    else:
        cur.execute(
            "update accounts set email = %s where account_id = "
            "(select account_id from accounts order by random() limit 1)",
            (fake.email(),),
        )


def delete_abandoned(cur, fake, rng):
    # Hard deletes are exactly what batch extracts miss and CDC catches.
    cur.execute(
        """delete from transactions
           where transaction_id = (select transaction_id from transactions
                                   where status = 'pending' and created_at < now() - interval '2 minutes'
                                   order by created_at limit 1)"""
    )


ACTIONS = [
    (new_transaction, 0.55),
    (resolve_pending, 0.30),
    (refund, 0.04),
    (lambda cur, fake, rng: create_account(cur, fake, rng), 0.04),
    (update_account, 0.05),
    (delete_abandoned, 0.02),
]


def live(conn, rate: float, rng: random.Random, fake: Faker) -> None:
    funcs, weights = zip(*ACTIONS, strict=True)
    n = 0
    with conn.cursor() as cur:
        while True:
            rng.choices(funcs, weights)[0](cur, fake, rng)
            n += 1
            if n % 100 == 0:
                print(f"{n} operations")
            time.sleep(1 / rate)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--dsn", default=os.getenv("PG_DSN", "postgresql://payments:payments@localhost:5432/payments"))
    p.add_argument("--backfill-days", type=int, default=0)
    p.add_argument("--per-day", type=int, default=2000)
    p.add_argument("--rate", type=float, default=5.0, help="live operations per second")
    p.add_argument("--seed", type=int, default=None)
    args = p.parse_args()

    rng = random.Random(args.seed)
    fake = Faker()
    Faker.seed(args.seed)

    with psycopg.connect(args.dsn) as conn:
        if args.backfill_days:
            backfill(conn, args.backfill_days, args.per_day, rng, fake)
        else:
            conn.autocommit = True
            live(conn, args.rate, rng, fake)


if __name__ == "__main__":
    main()
