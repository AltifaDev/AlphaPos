import urllib.request
import json

url = "https://your-supabase-project.supabase.co/rest/v1/"
anon_key = "your-anon-key"
merchant_id = "your-merchant-uuid"

def query_endpoint(endpoint):
    # Try with headers first
    req = urllib.request.Request(
        f"{url}{endpoint}",
        headers={
            "apikey": anon_key,
            "Authorization": f"Bearer {anon_key}",
            "x-merchant-id": merchant_id
        },
        method="GET"
    )
    try:
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode("utf-8"))
            print(f"[{endpoint} with x-merchant-id]: Success ({len(data)} rows)")
            for row in data:
                print(f"  {row.get('table_number')} - Floor {row.get('floor')} - {row.get('status')}")
    except Exception as e:
        print(f"[{endpoint} with x-merchant-id]: Error: {e}")

query_endpoint("restaurant_tables")
query_endpoint("tables")
