import random
import sys
import uuid
from collections import Counter
from datetime import date
from decimal import Decimal
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from settlements import BreakRates, build_settlement_rows  # noqa: E402

D = date(2026, 1, 5)


def ledger(n: int) -> list[dict]:
    return [{"transaction_id": str(uuid.uuid4()), "amount": Decimal("19.99"), "currency": "USD"} for _ in range(n)]


NO_BREAKS = BreakRates(0, 0, 0, 0, 0)


def test_clean_file_settles_every_captured_txn_once():
    captured = ledger(500)
    rows, truth = build_settlement_rows(captured, ledger(20), D, random.Random(1), NO_BREAKS)
    assert truth == []
    assert sorted(r["transaction_id"] for r in rows) == sorted(t["transaction_id"] for t in captured)
    assert all(r["amount"] == "19.99" for r in rows)


def test_same_seed_is_deterministic():
    captured, failed = ledger(300), ledger(30)
    a = build_settlement_rows(captured, failed, D, random.Random(42))
    b = build_settlement_rows(captured, failed, D, random.Random(42))
    assert a == b


def test_each_break_type_has_the_right_shape():
    captured, failed = ledger(2000), ledger(200)
    rates = BreakRates(missing=0.05, amount_mismatch=0.05, duplicate=0.05, orphan=0.01, status_mismatch=0.2)
    rows, truth = build_settlement_rows(captured, failed, D, random.Random(7), rates)

    counts = Counter(r["transaction_id"] for r in rows)
    amounts = {r["transaction_id"]: r["amount"] for r in rows}
    ledger_ids = {t["transaction_id"] for t in captured}
    failed_ids = {t["transaction_id"] for t in failed}

    for t in truth:
        tid, kind = t["transaction_id"], t["expected_break"]
        if kind == "MISSING_SETTLEMENT":
            assert counts[tid] == 0
        elif kind == "DUPLICATE_SETTLEMENT":
            assert counts[tid] == 2
        elif kind == "AMOUNT_MISMATCH":
            assert counts[tid] == 1 and amounts[tid] != "19.99"
        elif kind == "ORPHAN_SETTLEMENT":
            assert tid not in ledger_ids and tid not in failed_ids
        elif kind == "STATUS_MISMATCH":
            assert tid in failed_ids and counts[tid] == 1

    assert {t["expected_break"] for t in truth} == {
        "MISSING_SETTLEMENT",
        "AMOUNT_MISMATCH",
        "DUPLICATE_SETTLEMENT",
        "ORPHAN_SETTLEMENT",
        "STATUS_MISMATCH",
    }
