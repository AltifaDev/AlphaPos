import urllib.request
import json

supabase_url = 'https://sdmtkixrqkmwcpwoisrg.supabase.co'
supabase_key = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNkbXRraXhycWttd2Nwd29pc3JnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA4NDIxNjAsImV4cCI6MjA5NjQxODE2MH0.rjLwVE0ShXIFoT0k982XO_lVCQMsA4uTKMW1Su-NUws'
merchant_id = '163350b0-056d-4d5e-b5d4-24e7aac5ab6d'

headers = {
    'apikey': supabase_key,
    'Authorization': f'Bearer {supabase_key}',
    'Content-Type': 'application/json',
    'x-merchant-id': merchant_id
}

def query_table(name):
    url = f"{supabase_url}/rest/v1/{name}?select=*"
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode())
            print(f"Table '{name}': successfully fetched {len(data)} rows.")
            if data:
                print(f"Sample row keys: {list(data[0].keys())}")
                if name == "promotions":
                    for i, p in enumerate(data):
                        print(f"  Promo {i+1}: ID={p.get('id')} Title={p.get('title')} media_type={p.get('media_type')} is_active={p.get('is_active')} is_deleted={p.get('is_deleted')}")
    except Exception as e:
        print(f"Failed to query '{name}': {str(e)}")

query_table("promotions")
query_table("menu_items")
query_table("restaurant_tables")
query_table("merchants")
