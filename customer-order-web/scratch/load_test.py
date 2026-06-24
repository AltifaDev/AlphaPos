import json
import urllib.request
import urllib.error
import uuid
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

SUPABASE_URL = 'http://119.59.99.163'
SUPABASE_KEY = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH'
MERCHANT_ID = '163350b0-056d-4d5e-b5d4-24e7aac5ab6d'

headers = {
    "apikey": SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
    "Content-Type": "application/json",
    "x-merchant-id": MERCHANT_ID
}

# 1. Fetch the 40 LoadTest tables
def get_load_test_tables():
    url = f"{SUPABASE_URL}/rest/v1/restaurant_tables?table_number=like.LT-%25&order=table_number.asc&limit=40"
    req = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req) as res:
            tables = json.loads(res.read().decode('utf-8'))
            # Sort numerically by the number suffix
            tables.sort(key=lambda t: int(t['table_number'].split('-')[1]))
            return tables
    except Exception as e:
        print("Failed to fetch tables:", e)
        return []

# 2. Insert sessions for these tables
def create_sessions(tables):
    sessions = []
    session_map = {}
    for t in tables:
        session_id = str(uuid.uuid4())
        session_token = f"session-lt-{t['table_number'].split('-')[1]}-{str(uuid.uuid4().hex)[:6]}"
        sessions.append({
            "id": session_id,
            "table_id": t["id"],
            "table_number": t["table_number"],
            "session_token": session_token,
            "is_active": 1,
            "guest_count": 2,
            "merchant_id": MERCHANT_ID,
            "is_deleted": False,
            "created_at": "2026-06-24T01:57:00Z"
        })
        session_map[t["table_number"]] = session_token
    
    url = f"{SUPABASE_URL}/rest/v1/table_sessions"
    req = urllib.request.Request(url, data=json.dumps(sessions).encode('utf-8'), headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req) as res:
            print(f"Successfully created {len(sessions)} active table sessions.")
            return session_map
    except Exception as e:
        if hasattr(e, 'read'):
            print("Error creating sessions:", e.read().decode('utf-8'))
        else:
            print("Error creating sessions:", e)
        return {}

# 3. Submit single order
def submit_order(table_number, session_token):
    order_id = str(uuid.uuid4())
    payload = {
        "p_order": {
            "id": order_id,
            "order_number": f"ORD-LT-{table_number.split('-')[1]}-{str(uuid.uuid4().hex)[:4].upper()}",
            "table_number": table_number,
            "total": 175.0,
            "status": "preparing",
            "session_token": session_token,
            "guest_count": 2,
            "merchant_id": MERCHANT_ID,
            "created_at": "2026-06-24T01:57:00Z"
        },
        "p_items": [
            {
                "id": str(uuid.uuid4()),
                "order_id": order_id,
                "item_name": "Classic Som Tum Thai",
                "quantity": 1,
                "price": 85.0,
                "status": "cooking",
                "item_id": "eaa14775-851a-5e23-8139-25c92ce38a0b",
                "merchant_id": MERCHANT_ID,
                "notes": None
            },
            {
                "id": str(uuid.uuid4()),
                "order_id": order_id,
                "item_name": "Som Tum Boo Plarah",
                "quantity": 1,
                "price": 90.0,
                "status": "cooking",
                "item_id": "b5fc717b-4399-5e82-ada9-659920a3c71f",
                "merchant_id": MERCHANT_ID,
                "notes": None
            }
        ],
        "p_modifiers": []
    }
    
    url = f"{SUPABASE_URL}/rest/v1/rpc/create_customer_order"
    start_time = time.time()
    req = urllib.request.Request(url, data=json.dumps(payload).encode('utf-8'), headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req) as response:
            resp_body = response.read().decode('utf-8')
            latency = time.time() - start_time
            return True, table_number, latency, resp_body
    except urllib.error.HTTPError as e:
        latency = time.time() - start_time
        try:
            err_body = e.read().decode('utf-8')
        except:
            err_body = str(e)
        return False, table_number, latency, f"HTTP {e.code}: {err_body}"
    except Exception as e:
        latency = time.time() - start_time
        return False, table_number, latency, str(e)

def run_stress_test():
    print("Step 1: Fetching load test tables...")
    tables = get_load_test_tables()
    if not tables:
        print("No tables found. Make sure tables are generated.")
        return
    print(f"Found {len(tables)} load test tables.")
    
    print("\nStep 2: Establishing active table sessions...")
    session_map = create_sessions(tables)
    if not session_map:
        print("Failed to establish sessions. Aborting.")
        return
        
    print("\nStep 3: Launching stress test (40 concurrent orders)...")
    results = []
    start_all = time.time()
    
    with ThreadPoolExecutor(max_workers=40) as executor:
        futures = {
            executor.submit(submit_order, t["table_number"], session_map[t["table_number"]]): t 
            for t in tables
        }
        
        for future in as_completed(futures):
            success, table_num, latency, details = future.result()
            results.append({
                "success": success,
                "table": table_num,
                "latency": latency,
                "details": details
            })
            status = "SUCCESS" if success else "FAILED"
            print(f"Table {table_num:12} | Status: {status:7} | Latency: {latency:.3f}s")
            
    total_time = time.time() - start_all
    successes = [r for r in results if r["success"]]
    failures = [r for r in results if not r["success"]]
    
    print("\n" + "="*50)
    print("CONCURRENT STRESS TEST SUMMARY")
    print("="*50)
    print(f"Total concurrent orders: {len(results)}")
    print(f"Successful submissions : {len(successes)}")
    print(f"Failed submissions     : {len(failures)}")
    print(f"Success Rate           : {(len(successes)/len(results))*100:.1f}%")
    print(f"Total stress test time : {total_time:.3f}s")
    
    if successes:
        latencies = [r["latency"] for r in successes]
        print(f"Average Latency        : {sum(latencies)/len(latencies):.3f}s")
        print(f"Min Latency            : {min(latencies):.3f}s")
        print(f"Max Latency            : {max(latencies):.3f}s")
        
    if failures:
        print("\n--- Failure Details ---")
        for f in failures:
            print(f"Table {f['table']}: {f['details']}")

if __name__ == "__main__":
    run_stress_test()
