"""Simulated payment-processor settlement file for one business date.

Real processors (Stripe, Adyen, ...) send a daily file of what they actually settled.
This script builds that file from the ledger and deliberately injects breaks, and
writes a ground-truth file so you can score how well the reconciliation catches them.

  python generator/settlements.py --date 2026-09-24                    # -> S3
  python generator/settlements.py --date 2026-09-24 --local-dir local_out
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import os
import random
import uuid
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from decimal import Decimal
from pathlib import Path

FIELDS = ["settlement_id", "transaction_id", "amount", "currency", "fee", "settled_at", "batch_date"]


@dataclass(frozen=True)
class BreakRates:
    missing: float = 0.010  # ledger says captured, processor never settled
    amount_mismatch: float = 0.010  # settled for a different amount
    duplicate: float = 0.005  # settled twice
    orphan: float = 0.003  # settlement with no ledger transaction (per captured txn)
    status_mismatch: float = 0.020  # ledger says failed, processor settled it (per failed txn)


DEFAULT_RATES = BreakRates()


def _fee(amount: Decimal) -> Decimal:
    return (amount * Decimal("0.029") + Decimal("0.30")).quantize(Decimal("0.01"))


def build_settlement_rows(
    captured: list[dict],
    failed: list[dict],
    batch_date: date,
    rng: random.Random,
    rates: BreakRates = DEFAULT_RATES,
) -> tuple[list[dict], list[dict]]:
    """Pure function: ledger rows in, (settlement rows, expected breaks) out."""
    settled_at = datetime.combine(batch_date + timedelta(days=1), time(2, 0), tzinfo=UTC)
    rows: list[dict] = []
    truth: list[dict] = []

    def row(txn_id: str, amount: Decimal, currency: str) -> dict:
        return {
            "settlement_id": str(uuid.UUID(int=rng.getrandbits(128), version=4)),
            "transaction_id": txn_id,
            "amount": f"{amount:.2f}",
            "currency": currency,
            "fee": f"{_fee(amount):.2f}",
            "settled_at": settled_at.isoformat(),
            "batch_date": batch_date.isoformat(),
        }

    t_missing = rates.missing
    t_mismatch = t_missing + rates.amount_mismatch
    t_duplicate = t_mismatch + rates.duplicate

    for txn in captured:
        tid, amt, cur = str(txn["transaction_id"]), Decimal(txn["amount"]), txn["currency"]
        r = rng.random()
        if r < t_missing:
            truth.append({"transaction_id": tid, "expected_break": "MISSING_SETTLEMENT"})
        elif r < t_mismatch:
            drift = Decimal(str(round(rng.uniform(0.01, 5.00), 2))) * rng.choice([1, -1])
            new_amt = max(amt + drift, Decimal("0.01"))
            rows.append(row(tid, new_amt, cur))
            truth.append({"transaction_id": tid, "expected_break": "AMOUNT_MISMATCH"})
        elif r < t_duplicate:
            rows.extend([row(tid, amt, cur), row(tid, amt, cur)])
            truth.append({"transaction_id": tid, "expected_break": "DUPLICATE_SETTLEMENT"})
        else:
            rows.append(row(tid, amt, cur))

    for txn in failed:
        if rng.random() < rates.status_mismatch:
            tid = str(txn["transaction_id"])
            rows.append(row(tid, Decimal(txn["amount"]), txn["currency"]))
            truth.append({"transaction_id": tid, "expected_break": "STATUS_MISMATCH"})

    for _ in range(round(len(captured) * rates.orphan)):
        tid = str(uuid.UUID(int=rng.getrandbits(128), version=4))
        rows.append(row(tid, Decimal(str(round(rng.uniform(5, 500), 2))), "USD"))
        truth.append({"transaction_id": tid, "expected_break": "ORPHAN_SETTLEMENT"})

    rng.shuffle(rows)
    return rows, truth


def fetch_ledger(dsn: str, batch_date: date) -> tuple[list[dict], list[dict]]:
    import psycopg
    from psycopg.rows import dict_row

    sql = """select transaction_id, amount, currency, status from transactions
             where (created_at at time zone 'UTC')::date = %s and status <> 'pending'"""
    with psycopg.connect(dsn, row_factory=dict_row) as conn:
        txns = conn.execute(sql, (batch_date,)).fetchall()
    captured = [t for t in txns if t["status"] in ("succeeded", "refunded")]
    failed = [t for t in txns if t["status"] == "failed"]
    return captured, failed


def to_csv(rows: list[dict]) -> str:
    buf = io.StringIO()
    writer = csv.DictWriter(buf, fieldnames=FIELDS)
    writer.writeheader()
    writer.writerows(rows)
    return buf.getvalue()


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--date", required=True, type=date.fromisoformat)
    p.add_argument("--dsn", default=os.getenv("PG_DSN", "postgresql://payments:payments@localhost:5432/payments"))
    p.add_argument("--bucket", default=os.getenv("S3_BUCKET"))
    p.add_argument("--local-dir", default=None, help="write here instead of S3")
    p.add_argument("--seed", type=int, default=None)
    args = p.parse_args()

    rng = random.Random(args.seed)
    captured, failed = fetch_ledger(args.dsn, args.date)
    rows, truth = build_settlement_rows(captured, failed, args.date, rng)

    d = args.date.isoformat()
    files = {
        f"settlements/dt={d}/settlements_{d}.csv": to_csv(rows),
        # Not loaded into Snowflake on purpose: it's the answer key.
        f"ground_truth/dt={d}/expected_breaks.json": json.dumps(truth, indent=2),
    }

    if args.local_dir:
        for key, body in files.items():
            path = Path(args.local_dir) / key
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(body)
    else:
        import boto3

        if not args.bucket:
            raise SystemExit("Set S3_BUCKET or pass --local-dir")
        s3 = boto3.client("s3")
        for key, body in files.items():
            s3.put_object(Bucket=args.bucket, Key=key, Body=body.encode())

    print(
        f"{d}: {len(captured)} captured, {len(failed)} failed -> "
        f"{len(rows)} settlement rows, {len(truth)} injected breaks"
    )


if __name__ == "__main__":
    main()
