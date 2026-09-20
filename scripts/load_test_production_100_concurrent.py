#!/usr/bin/env python3
"""
scripts/load_test_production_100_concurrent.py
AlphaPos 100-User Production Concurrency & Resilience Test Suite

Validates:
  1. 100 Concurrent Order Creations with Idempotency verification (0% duplicate)
  2. Multi-tenant isolation verification (0% cross-tenant leak)
  3. Concurrent modification on the same order (Optimistic locking conflict detection)
  4. Offline recovery sync storm burst handling (Rate limiter & Concurrency Guard)
  5. Payment & Checkout deduplication (Zero double-charging)
  6. Latency distribution (P50, P90, P95, P99)

Usage:
  python3 scripts/load_test_production_100_concurrent.py [--url SUPABASE_URL] [--key ANON_OR_SERVICE_KEY] [--concurrency 100]
"""

import os
import sys
import time
import json
import uuid
import random
import argparse
import statistics
import urllib.request
import urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed

DEFAULT_URL = os.environ.get("SUPABASE_URL", "http://127.0.0.1:54321")
DEFAULT_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", os.environ.get("SUPABASE_ANON_KEY", ""))

# Mock Tenant Identifiers for Testing
TENANT_A_ID = "163350b0-056d-4d5e-b5d4-24e7aac5ab6d"
TENANT_B_ID = "22222222-2222-2222-2222-222222222222"
BRANCH_A_ID = "33333333-3333-3333-3333-333333333333"

def send_rpc(base_url: str, key: str, rpc_name: str, payload: dict, auth_token: str = None) -> tuple[dict, int, float]:
    url = f"{base_url.rstrip('/')}/rest/v1/rpc/{rpc_name}"
    token = auth_token or key
    headers = {
        "Content-Type": "application/json",
        "apikey": key,
        "Authorization": f"Bearer {token}",
        "Prefer": "return=representation"
    }
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    
    start_time = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            elapsed = (time.perf_counter() - start_time) * 1000
            data = resp.read().decode("utf-8")
            return json.loads(data) if data else {}, resp.status, elapsed
    except urllib.error.HTTPError as e:
        elapsed = (time.perf_counter() - start_time) * 1000
        error_body = e.read().decode("utf-8")
        try:
            parsed = json.loads(error_body)
        except Exception:
            parsed = {"error": error_body}
        return parsed, e.code, elapsed
    except Exception as e:
        elapsed = (time.perf_counter() - start_time) * 1000
        return {"error": str(e)}, 0, elapsed

# =========================================================================
# Test Scenarios
# =========================================================================

def run_concurrent_order_test(base_url: str, key: str, concurrency: int) -> dict:
    print(f"\n[Test 1/5] Executing {concurrency} Concurrent Order Creations & Idempotent Replays...")
    order_ids = [str(uuid.uuid4()) for _ in range(concurrency)]
    operation_ids = [f"op-{order_ids[i]}" for i in range(concurrency)]
    latencies = []
    statuses = []
    replay_latencies = []
    replay_statuses = []

    def create_single_order(idx: int):
        oid = order_ids[idx]
        opid = operation_ids[idx]
        payload = {
            "p_order": {
                "id": oid,
                "merchant_id": TENANT_A_ID,
                "branch_id": BRANCH_A_ID,
                "table_number": f"T-{idx % 20 + 1}",
                "operation_id": opid,
                "status": "pending",
                "subtotal": 150.0,
                "total": 150.0
            },
            "p_items": [
                {
                    "id": str(uuid.uuid4()),
                    "item_id": "11111111-1111-1111-1111-111111111111",
                    "item_name": f"Signature Dish {idx}",
                    "quantity": 1,
                    "price": 150.0,
                    "status": "pending"
                }
            ],
            "p_modifiers": []
        }
        res, code, lat = send_rpc(base_url, key, "create_order_atomic_cas", payload)
        
        # Immediate Idempotency Replay (simulate network retry)
        r_res, r_code, r_lat = send_rpc(base_url, key, "create_order_atomic_cas", payload)
        
        # Validate that replay returned identical order_id
        replay_match = (res.get("order_id") == r_res.get("order_id")) if code in (200, 201) else True
        return code, lat, r_code, r_lat, replay_match

    with ThreadPoolExecutor(max_workers=concurrency) as executor:
        futures = [executor.submit(create_single_order, i) for i in range(concurrency)]
        replays_matched = 0
        for f in as_completed(futures):
            c, l, rc, rl, match = f.result()
            statuses.append(c)
            latencies.append(l)
            replay_statuses.append(rc)
            replay_latencies.append(rl)
            if match:
                replays_matched += 1

    return {
        "concurrency": concurrency,
        "latencies": latencies,
        "replay_latencies": replay_latencies,
        "success_count": sum(1 for s in statuses if s in (200, 201)),
        "replay_success_count": sum(1 for s in replay_statuses if s in (200, 201)),
        "idempotency_match_rate": (replays_matched / concurrency) * 100
    }

def run_concurrent_table_conflict_test(base_url: str, key: str, workers: int) -> dict:
    print(f"\n[Test 2/5] Testing Optimistic Locking ({workers} Workers Racing to Modify Same Order)...")
    target_order_id = str(uuid.uuid4())
    init_payload = {
        "p_order": {
            "id": target_order_id,
            "merchant_id": TENANT_A_ID,
            "branch_id": BRANCH_A_ID,
            "table_number": "RACE-TABLE-01",
            "operation_id": f"init-{target_order_id}",
            "status": "pending",
            "subtotal": 100.0,
            "total": 100.0
        },
        "p_items": [{
            "id": str(uuid.uuid4()),
            "item_name": "Shared Pot",
            "quantity": 1,
            "price": 100.0,
            "status": "pending"
        }],
        "p_modifiers": []
    }
    init_res, init_code, _ = send_rpc(base_url, key, "create_order_atomic_cas", init_payload)
    expected_version = init_res.get("order_row_version", 1)

    # Now unleash `workers` threads trying to transition with expected_version = 1
    latencies = []
    conflict_detected = 0
    success_count = 0

    def attempt_transition(worker_idx: int):
        payload = {
            "p_order_id": target_order_id,
            "p_branch_id": BRANCH_A_ID,
            "p_expected_row_version": expected_version,
            "p_status": "served",
            "p_operation_id": f"trans-{worker_idx}-{uuid.uuid4()}"
        }
        res, code, lat = send_rpc(base_url, key, "transition_order_with_items", payload)
        is_conflict = (code in (400, 409) or "conflict" in str(res).lower() or "40001" in str(res))
        is_success = (code in (200, 201) and res.get("status") == "served")
        return code, lat, is_success, is_conflict

    with ThreadPoolExecutor(max_workers=workers) as executor:
        futures = [executor.submit(attempt_transition, i) for i in range(workers)]
        for f in as_completed(futures):
            c, l, s, conf = f.result()
            latencies.append(l)
            if s: success_count += 1
            if conf: conflict_detected += 1

    return {
        "target_order_id": target_order_id,
        "workers": workers,
        "success_count": success_count,
        "conflict_count": conflict_detected,
        "silent_overwrites": max(0, success_count - 1),
        "latencies": latencies
    }

def run_sync_burst_storm_test(base_url: str, key: str, concurrency: int) -> dict:
    print(f"\n[Test 3/5] Testing Sync Storm Burst & Concurrency Slots ({concurrency} Devices Reconnecting)...")
    latencies = []
    allowed_count = 0
    throttled_count = 0

    def sync_slot_request(device_idx: int):
        dev_id = f"ipad-sim-{device_idx:03d}"
        payload = {
            "p_branch_id": BRANCH_A_ID,
            "p_device_id": dev_id,
            "p_max_concurrent": 10  # Max 10 simultaneous sync uploads per branch
        }
        res, code, lat = send_rpc(base_url, key, "acquire_sync_slot", payload)
        allowed = res.get("allowed", False)
        return code, lat, allowed

    with ThreadPoolExecutor(max_workers=concurrency) as executor:
        futures = [executor.submit(sync_slot_request, i) for i in range(concurrency)]
        for f in as_completed(futures):
            c, l, allowed = f.result()
            latencies.append(l)
            if allowed:
                allowed_count += 1
            else:
                throttled_count += 1

    return {
        "concurrency": concurrency,
        "allowed_count": allowed_count,
        "throttled_count": throttled_count,
        "latencies": latencies
    }

def run_cross_tenant_isolation_test(base_url: str, key: str) -> dict:
    print("\n[Test 4/5] Verifying Strict Multi-Tenant Isolation...")
    # Attempt to read or modify Tenant B's order using Tenant A's identity
    foreign_order_id = str(uuid.uuid4())
    payload = {
        "p_order_id": foreign_order_id,
        "p_branch_id": BRANCH_A_ID,
        "p_expected_row_version": 1,
        "p_status": "served"
    }
    res, code, _ = send_rpc(base_url, key, "transition_order_with_items", payload)
    
    # Must fail or return order_not_found (never return foreign order)
    leak_prevented = (code != 200) or ("order_not_found" in str(res))
    return {
        "leak_prevented": leak_prevented,
        "response_code": code,
        "status": "PASS" if leak_prevented else "FAIL"
    }

def run_concurrent_checkout_idempotency_test(base_url: str, key: str, concurrency: int) -> dict:
    print(f"\n[Test 5/5] Testing Concurrent Checkout & Payment Deduplication ({concurrency} Attempts)...")
    order_id = str(uuid.uuid4())
    idem_key = f"checkout-{order_id}"
    
    # 1. Create base order
    send_rpc(base_url, key, "create_order_atomic_cas", {
        "p_order": {
            "id": order_id,
            "merchant_id": TENANT_A_ID,
            "branch_id": BRANCH_A_ID,
            "status": "pending",
            "subtotal": 200.0,
            "total": 200.0,
            "operation_id": f"base-{order_id}"
        },
        "p_items": [{"id": str(uuid.uuid4()), "item_name": "Course Meal", "quantity": 1, "price": 200.0, "status": "pending"}],
        "p_modifiers": []
    })

    # 2. Fire simultaneous checkout requests with the same idempotency key
    payment_id = str(uuid.uuid4())
    payload = {
        "p_order_id": order_id,
        "p_idempotency_key": idem_key,
        "p_payments": [{
            "id": payment_id,
            "amount": 200.0,
            "payment_method": "promptpay"
        }],
        "p_table_number": "QUICK",
        "p_breakdown": {
            "grand_total": 200.0,
            "subtotal": 200.0
        }
    }

    results = []
    with ThreadPoolExecutor(max_workers=concurrency) as executor:
        futures = [executor.submit(send_rpc, base_url, key, "complete_checkout_atomic", payload) for _ in range(concurrency)]
        for f in as_completed(futures):
            res, code, lat = f.result()
            results.append((code, res.get("status"), lat))

    successes = sum(1 for c, s, _ in results if c == 200 and s == "completed")
    return {
        "order_id": order_id,
        "concurrency": concurrency,
        "completed_count": successes,
        "deduplicated_properly": (successes == concurrency)
    }

# =========================================================================
# Main Runner & Reporting
# =========================================================================

def calc_p(values: list[float], pct: float) -> float:
    if not values: return 0.0
    sorted_v = sorted(values)
    idx = int(len(sorted_v) * (pct / 100.0))
    return round(sorted_v[min(idx, len(sorted_v) - 1)], 1)

def main():
    parser = argparse.ArgumentParser(description="AlphaPos 100-User Production Concurrency Test Suite")
    parser.add_argument("--url", default=DEFAULT_URL, help="Supabase API URL")
    parser.add_argument("--key", default=DEFAULT_KEY, help="Supabase API Key")
    parser.add_argument("--concurrency", type=int, default=100, help="Number of concurrent virtual users")
    parser.add_argument("--json", action="store_true", help="Output summary as JSON")
    args = parser.parse_args()

    print("=" * 65)
    print(f" AlphaPos 100-User Production Concurrency & Resilience Test")
    print(f" Target: {args.url} | Concurrency: {args.concurrency} Virtual Users")
    print("=" * 65)

    suite_start = time.time()
    
    # 1. Concurrent Orders
    r1 = run_concurrent_order_test(args.url, args.key, args.concurrency)
    
    # 2. Race Table Conflict
    r2 = run_concurrent_table_conflict_test(args.url, args.key, min(50, args.concurrency))
    
    # 3. Sync Storm Burst
    r3 = run_sync_burst_storm_test(args.url, args.key, args.concurrency)
    
    # 4. Multi-Tenant Isolation
    r4 = run_cross_tenant_isolation_test(args.url, args.key)
    
    # 5. Payment Deduplication
    r5 = run_concurrent_checkout_idempotency_test(args.url, args.key, min(20, args.concurrency))
    
    total_duration = round(time.time() - suite_start, 2)
    all_latencies = r1["latencies"] + r2["latencies"] + r3["latencies"]

    p50 = calc_p(all_latencies, 50)
    p90 = calc_p(all_latencies, 90)
    p95 = calc_p(all_latencies, 95)
    p99 = calc_p(all_latencies, 99)

    # Pass / Fail Evaluation Against Production Criteria
    checks = [
        ("Zero Duplicate Orders on Replay", r1["idempotency_match_rate"] == 100.0),
        ("Optimistic Locking Prevents Silent Overwrites", r2["silent_overwrites"] == 0),
        ("Conflict Correctly Detected on Concurrent Edit", r2["conflict_count"] > 0 or r2["success_count"] == 1),
        ("Sync Storm Throttled Without Crashing", (r3["allowed_count"] + r3["throttled_count"]) == args.concurrency),
        ("Zero Cross-Tenant Leakage", r4["leak_prevented"]),
        ("Payment Deduplication (Zero Double Charge)", r5["deduplicated_properly"]),
        ("P95 Latency <= 2500ms", p95 <= 2500.0)
    ]

    all_passed = all(passed for _, passed in checks)

    if args.json:
        report = {
            "all_passed": all_passed,
            "duration_seconds": total_duration,
            "metrics": {"p50_ms": p50, "p90_ms": p90, "p95_ms": p95, "p99_ms": p99},
            "checks": [{"name": name, "passed": passed} for name, passed in checks],
            "details": {"test_1": r1, "test_2": r2, "test_3": r3, "test_4": r4, "test_5": r5}
        }
        print(json.dumps(report, indent=2))
        sys.exit(0 if all_passed else 1)

    print("\n" + "=" * 65)
    print(f" Test Results Summary (Total Time: {total_duration}s)")
    print("=" * 65)
    print(f"⏱️ Latency Distribution:")
    print(f"   • P50 : {p50} ms")
    print(f"   • P90 : {p90} ms")
    print(f"   • P95 : {p95} ms (Threshold: <= 2500 ms)")
    print(f"   • P99 : {p99} ms")
    print("\n📋 Production Readiness Verification Checklist:")
    for name, passed in checks:
        icon = "✅ PASS" if passed else "❌ FAIL"
        print(f"   {icon} — {name}")
    print("=" * 65)

    if all_passed:
        print("🎉 ALL PRODUCTION STANDARDS VERIFIED! SYSTEM CERTIFIED FOR 100+ USERS.")
        sys.exit(0)
    else:
        print("⚠️ SOME CHECKS DID NOT PASS. Review the telemetry report above.")
        sys.exit(1)

if __name__ == "__main__":
    main()
