import urllib.request
import json

SUPABASE_URL = 'http://119.59.99.163'
SUPABASE_KEY = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH'
MERCHANT_ID = '163350b0-056d-4d5e-b5d4-24e7aac5ab6d'

def make_request(path, method="GET", body=None, headers=None):
    url = f"{SUPABASE_URL}/rest/v1/{path}"
    req_headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "x-merchant-id": MERCHANT_ID
    }
    if headers:
        req_headers.update(headers)
        
    data = None
    if body is not None:
        data = json.dumps(body).encode('utf-8')
        req_headers["Content-Type"] = "application/json"
        
    req = urllib.request.Request(url, data=data, headers=req_headers, method=method)
    try:
        with urllib.request.urlopen(req) as response:
            return json.loads(response.read().decode('utf-8'))
    except Exception as e:
        if hasattr(e, 'read'):
            error_body = e.read().decode('utf-8')
            print(f"Error {path}: {e} - Body: {error_body}")
        else:
            print(f"Error {path}: {e}")
        return None

def main():
    print("=== Table Sessions in Supabase ===")
    sessions = make_request("table_sessions?select=*")
    if sessions:
        print(f"Total sessions: {len(sessions)}")
        for s in sessions[:10]:
            print(s)
            
    print("\n=== Recent Orders in Supabase ===")
    orders = make_request("orders?select=*&order=created_at.desc&limit=10")
    if orders:
        print(f"Total orders returned: {len(orders)}")
        for o in orders:
            print(o)

if __name__ == "__main__":
    main()
