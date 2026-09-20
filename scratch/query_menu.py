import urllib.request
import json
import os

url = os.environ.get("SUPABASE_URL", "http://119.59.99.163").rstrip("/") + "/rest/v1/menu_items"
anon_key = os.environ["SUPABASE_ANON_KEY"]

req = urllib.request.Request(
    url,
    headers={
        "apikey": anon_key,
        "Authorization": f"Bearer {anon_key}"
    },
    method="GET"
)

try:
    with urllib.request.urlopen(req) as response:
        print("Status:", response.status)
        print("Data:", response.read().decode("utf-8"))
except Exception as e:
    print("Error:", e)
    if hasattr(e, 'read'):
        print(e.read().decode("utf-8"))
