import sqlite3
import urllib.request
import json

SUPABASE_URL = 'http://119.59.99.163'
SUPABASE_KEY = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH'
MERCHANT_ID = '163350b0-056d-4d5e-b5d4-24e7aac5ab6d'

def get_supabase(path):
    url = f"{SUPABASE_URL}/rest/v1/{path}"
    req = urllib.request.Request(url, headers={
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "x-merchant-id": MERCHANT_ID
    })
    try:
        with urllib.request.urlopen(req) as response:
            return json.loads(response.read().decode('utf-8'))
    except Exception as e:
        print(f"Error reading Supabase {path}: {e}")
        return []

def main():
    # SQLite Modifiers
    conn = sqlite3.connect('/Users/mac/Documents/AlphaPos/customer-order-web/alphapos.db')
    cursor = conn.cursor()
    cursor.execute("SELECT id, name, extra_price, modifier_group_id FROM modifiers")
    sqlite_mods = cursor.fetchall()
    conn.close()
    
    print(f"SQLite Modifiers count: {len(sqlite_mods)}")
    for mod in sqlite_mods[:5]:
        print(f"  SQLite Mod: {mod}")

    # Supabase Modifiers
    supabase_mods = get_supabase("modifiers?select=*")
    print(f"Supabase Modifiers count: {len(supabase_mods)}")
    for mod in supabase_mods[:5]:
        print(f"  Supabase Mod: {mod['id']}, {mod['name']}, {mod['extra_price']}, {mod['modifier_group_id']}")

    # Let's check menu_items
    conn = sqlite3.connect('/Users/mac/Documents/AlphaPos/customer-order-web/alphapos.db')
    cursor = conn.cursor()
    cursor.execute("SELECT id, name, price FROM menu_items")
    sqlite_menu = cursor.fetchall()
    conn.close()
    
    print(f"\nSQLite Menu Items count: {len(sqlite_menu)}")
    for item in sqlite_menu[:5]:
        print(f"  SQLite Item: {item}")

    supabase_menu = get_supabase("menu_items?select=*")
    print(f"Supabase Menu Items count: {len(supabase_menu)}")
    for item in supabase_menu[:5]:
        print(f"  Supabase Item: {item['id']}, {item['name']}, {item['price']}")

if __name__ == "__main__":
    main()
