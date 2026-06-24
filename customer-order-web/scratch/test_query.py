import json
import urllib.request
import urllib.error

SUPABASE_URL = 'http://119.59.99.163'
SUPABASE_KEY = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH'
MERCHANT_ID = '163350b0-056d-4d5e-b5d4-24e7aac5ab6d'

headers = {
    "apikey": SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
    "Content-Type": "application/json",
    "x-merchant-id": MERCHANT_ID
}

url = f"{SUPABASE_URL}/rest/v1/restaurant_tables?limit=100"
req = urllib.request.Request(url, headers=headers, method="GET")

try:
    with urllib.request.urlopen(req) as res:
        print("Status:", res.status)
        print("Headers:", res.headers)
        body = res.read().decode('utf-8')
        print("Body:", body)
except urllib.error.HTTPError as e:
    print("HTTP Error:", e.code, e.reason)
    print("Body:", e.read().decode('utf-8'))
except Exception as e:
    print("Error:", e)
