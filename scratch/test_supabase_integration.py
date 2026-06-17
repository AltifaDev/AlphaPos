import urllib.request
import json
import uuid
from datetime import datetime

url = "https://your-supabase-project.supabase.co/rest/v1/"
anon_key = "your-anon-key"

headers = {
    "apikey": anon_key,
    "Authorization": f"Bearer {anon_key}",
    "Content-Type": "application/json",
    "Prefer": "return=representation"
}

def run_request(endpoint, method="GET", payload=None):
    req_url = f"{url}{endpoint}"
    data = json.dumps(payload).encode("utf-8") if payload else None
    req = urllib.request.Request(req_url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as response:
            return json.loads(response.read().decode("utf-8")), response.status
    except urllib.error.HTTPError as e:
        error_content = e.read().decode("utf-8")
        print(f"HTTP Error {e.code} for {method} {endpoint}: {error_content}")
        raise e

def test_supabase_flow():
    print("Starting Supabase Integration Flow Test...")
    
    # 1. Check table_sessions insert
    session_id = str(uuid.uuid4())
    session_token = f"test-session-{uuid.uuid4().hex[:6]}"
    session_payload = {
        "id": session_id,
        "table_number": "4",
        "session_token": session_token,
        "is_active": 1,
        "guest_count": 4
    }
    print("Inserting table_session...")
    res, status = run_request("table_sessions", "POST", session_payload)
    assert status == 201 or status == 200
    print("Successfully inserted table_session.")

    # 2. Check table_sessions query
    print("Querying table_session...")
    res, status = run_request(f"table_sessions?session_token=eq.{session_token}")
    assert len(res) == 1
    assert res[0]["table_number"] == "4"
    print("Successfully queried table_session.")

    # 3. Insert order
    order_id = str(uuid.uuid4())
    order_number = f"ORD-TEST-{uuid.uuid4().hex[:4].upper()}"
    order_payload = {
        "id": order_id,
        "order_number": order_number,
        "table_number": "4",
        "total": 350.00,
        "status": "preparing"
    }
    print("Inserting order...")
    res, status = run_request("orders", "POST", order_payload)
    assert status == 201 or status == 200
    print("Successfully inserted order.")

    # 4. Insert order item
    item_id = str(uuid.uuid4())
    item_payload = {
        "id": item_id,
        "order_id": order_id,
        "item_name": "Tom Yum Goong",
        "quantity": 1,
        "price": 280.00,
        "status": "cooking",
        "item_id": "app3"
    }
    print("Inserting order item...")
    res, status = run_request("order_items", "POST", item_payload)
    assert status == 201 or status == 200
    print("Successfully inserted order item.")

    # 5. Insert payment
    payment_id = str(uuid.uuid4())
    payment_payload = {
        "id": payment_id,
        "order_id": order_id,
        "amount": 350.00,
        "payment_method": "cash",
        "status": "completed"
    }
    print("Inserting payment...")
    res, status = run_request("payments", "POST", payment_payload)
    assert status == 201 or status == 200
    print("Successfully inserted payment.")

    # 6. Insert service request
    request_id = str(uuid.uuid4())
    request_payload = {
        "id": request_id,
        "table_number": "4",
        "request_type": "water",
        "status": "pending"
    }
    print("Inserting service request...")
    res, status = run_request("service_requests", "POST", request_payload)
    assert status == 201 or status == 200
    print("Successfully inserted service request.")

    # 7. Clean up test data
    print("Cleaning up test data...")
    run_request(f"service_requests?id=eq.{request_id}", "DELETE")
    run_request(f"payments?id=eq.{payment_id}", "DELETE")
    run_request(f"order_items?id=eq.{item_id}", "DELETE")
    run_request(f"orders?id=eq.{order_id}", "DELETE")
    run_request(f"table_sessions?id=eq.{session_id}", "DELETE")
    print("Clean up complete.")
    print("All Supabase integration tests passed successfully!")

if __name__ == "__main__":
    try:
        test_supabase_flow()
    except Exception as e:
        print(f"Test failed: {e}")
