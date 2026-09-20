import urllib.request
import json
import os

rest_url = os.environ.get("SUPABASE_URL", "http://119.59.99.163").rstrip("/") + "/rest/v1/restaurant_tables"
service_role = os.environ["SUPABASE_SERVICE_ROLE_KEY"]

req_query = urllib.request.Request(
    rest_url,
    headers={
        "apikey": service_role,
        "Authorization": f"Bearer {service_role}"
    },
    method="GET"
)

try:
    with urllib.request.urlopen(req_query) as response:
        tables = json.loads(response.read().decode('utf-8'))
        print(f"Tables retrieved with service_role: {len(tables)}")
        for t in tables:
            print(f"ID: {t.get('id')} - Merchant: {t.get('merchant_id')} - Table {t.get('table_number')} (Floor {t.get('floor')}): posX={t.get('position_x')}, posY={t.get('position_y')}, status={t.get('status')}, is_deleted={t.get('is_deleted')}")
except urllib.error.HTTPError as e:
    print("Failed to fetch tables with service_role (HTTP Error):", e.code)
    print("Response body:", e.read().decode('utf-8'))
except Exception as e:
    print("Failed to fetch tables with service_role:", e)
