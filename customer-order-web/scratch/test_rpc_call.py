import urllib.request
import urllib.error
import json
import uuid

SUPABASE_URL = 'http://119.59.99.163'
SUPABASE_KEY = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH'
MERCHANT_ID = '163350b0-056d-4d5e-b5d4-24e7aac5ab6d'

def test_rpc(use_header=True):
    order_id = str(uuid.uuid4())
    item_id = str(uuid.uuid4())
    payload = {
        "p_order": {
            "id": order_id,
            "order_number": f"ORD-TEST-{str(uuid.uuid4().int)[:4]}",
            "table_number": "3",
            "total": 100.0,
            "status": "preparing",
            "session_token": "session-6b2de69eff704", # existing active session for table 3 in Supabase
            "guest_count": 2,
            "merchant_id": MERCHANT_ID,
            "created_at": "2026-06-22T21:56:29Z"
        },
        "p_items": [
            {
                "id": item_id,
                "order_id": order_id,
                "item_name": "Test Som Tum",
                "quantity": 1,
                "price": 100.0,
                "status": "cooking",
                "item_id": None,
                "merchant_id": MERCHANT_ID,
                "notes": "No spicy"
            }
        ],
        "p_modifiers": []
    }
    
    url = f"{SUPABASE_URL}/rest/v1/rpc/create_customer_order"
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json"
    }
    if use_header:
        headers["x-merchant-id"] = MERCHANT_ID
        
    req = urllib.request.Request(url, data=json.dumps(payload).encode('utf-8'), headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req) as response:
            print("Response:", response.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        print(f"HTTP Error {e.code}: {e.reason}")
        print("Response body:", e.read().decode('utf-8'))
    except Exception as e:
        print("Error:", e)

if __name__ == "__main__":
    print("Testing RPC with x-merchant-id header:")
    test_rpc(use_header=True)
    print("\nTesting RPC WITHOUT x-merchant-id header:")
    test_rpc(use_header=False)
