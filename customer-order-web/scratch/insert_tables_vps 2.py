import json
import urllib.request
import urllib.error
import uuid

SUPABASE_URL = 'http://119.59.99.163'
SUPABASE_KEY = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH'
MERCHANT_ID = '163350b0-056d-4d5e-b5d4-24e7aac5ab6d'

headers = {
    "apikey": SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
    "Content-Type": "application/json",
    "x-merchant-id": MERCHANT_ID
}

tables = []
for i in range(101, 201):
    table_id = str(uuid.uuid4())
    tables.append({
        "id": table_id,
        "merchant_id": MERCHANT_ID,
        "table_number": f"LT-{i}",
        "capacity": 4,
        "status": "vacant",
        "qr_code_identifier": f"lt_{i}",
        "position_x": 100 + (i % 10) * 50,
        "position_y": 100 + (i // 10) * 50,
        "floor": 1,
        "is_deleted": False,
        "is_round": False,
        "zone": "LoadTestZone"
    })

url = f"{SUPABASE_URL}/rest/v1/restaurant_tables"
req = urllib.request.Request(url, data=json.dumps(tables).encode('utf-8'), headers=headers, method="POST")

try:
    with urllib.request.urlopen(req) as res:
        print("Success! Status:", res.status)
        print("Body:", res.read().decode('utf-8'))
except urllib.error.HTTPError as e:
    print("HTTP Error:", e.code, e.reason)
    print("Body:", e.read().decode('utf-8'))
except Exception as e:
    print("Error:", e)
