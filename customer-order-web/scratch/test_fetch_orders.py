import urllib.request
import urllib.parse
import json

SUPABASE_URL = 'http://119.59.99.163'
SUPABASE_KEY = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH'
MERCHANT_ID = '163350b0-056d-4d5e-b5d4-24e7aac5ab6d'

def test_fetch():
    # URL encode select params
    select_param = "*,order_items(*,order_item_modifiers(*)),payments(*)"
    query = urllib.parse.urlencode({
        "select": select_param,
        "session_token": "eq.session-3c15cd0162114",
        "order": "created_at.asc"
    })
    
    url = f"{SUPABASE_URL}/rest/v1/orders?{query}"
    
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "x-merchant-id": MERCHANT_ID
    }
    
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode('utf-8'))
            print("Status Code: 200 OK")
            print(f"Data returned: {len(data)} orders")
            if data:
                print("First order details:")
                print(json.dumps(data[0], indent=2))
    except urllib.error.HTTPError as e:
        print(f"HTTP Error {e.code}: {e.reason}")
        print("Response body:", e.read().decode('utf-8'))
    except Exception as e:
        print("Error:", e)

if __name__ == "__main__":
    test_fetch()
