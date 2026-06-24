import sqlite3
import urllib.request
import urllib.error
import json

SUPABASE_URL = 'http://119.59.99.163'
SUPABASE_KEY = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH'
MERCHANT_ID = '163350b0-056d-4d5e-b5d4-24e7aac5ab6d'

headers = {
    "apikey": SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
    "Content-Type": "application/json",
    "x-merchant-id": MERCHANT_ID
}

def sync_menu():
    # 1. Connect to SQLite and fetch all menu items
    conn = sqlite3.connect('/Users/mac/Documents/AlphaPos/customer-order-web/alphapos.db')
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM menu_items")
    rows = cursor.fetchall()
    conn.close()
    
    print(f"Read {len(rows)} menu items from SQLite.")
    
    # 2. Map to Supabase structure
    menu_items = []
    for row in rows:
        item = dict(row)
        
        # parse json translations if they are strings
        name_translations = {}
        if item.get('name_translations'):
            try:
                name_translations = json.loads(item['name_translations'])
            except:
                name_translations = {}
                
        desc_translations = {}
        if item.get('description_translations'):
            try:
                desc_translations = json.loads(item['description_translations'])
            except:
                desc_translations = {}

        menu_items.append({
            "id": item["id"],
            "merchant_id": MERCHANT_ID,
            "name": item["name"],
            "description": item.get("description"),
            "price": float(item["price"]),
            "category": item["category"],
            "emoji": item.get("emoji"),
            "img_class": item.get("img_class"),
            "image_url": item.get("image_url"),
            "name_translations": name_translations,
            "description_translations": desc_translations,
            "is_deleted": False
        })
        
    # 3. Post to Supabase
    url = f"{SUPABASE_URL}/rest/v1/menu_items"
    req = urllib.request.Request(url, data=json.dumps(menu_items).encode('utf-8'), headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req) as res:
            print("Successfully synced menu items to VPS. Status:", res.status)
    except urllib.error.HTTPError as e:
        print("HTTP Error syncing menu items:", e.code, e.reason)
        print("Body:", e.read().decode('utf-8'))
    except Exception as e:
        print("Error syncing menu items:", e)

if __name__ == "__main__":
    sync_menu()
