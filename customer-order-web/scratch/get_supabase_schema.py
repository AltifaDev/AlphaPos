import urllib.request
import json

SUPABASE_URL = 'http://119.59.99.163'
SUPABASE_KEY = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH'
MERCHANT_ID = '163350b0-056d-4d5e-b5d4-24e7aac5ab6d'

def query_sql(sql):
    url = f"{SUPABASE_URL}/rest/v1/rpc/execute_sql"
    payload = {"query": sql}
    req = urllib.request.Request(url, data=json.dumps(payload).encode('utf-8'), headers={
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json"
    }, method="POST")
    try:
        with urllib.request.urlopen(req) as response:
            return json.loads(response.read().decode('utf-8'))
    except Exception as e:
        if hasattr(e, 'read'):
            print("Error executing SQL:", e.read().decode('utf-8'))
        else:
            print("Error executing SQL:", e)
        return None

def main():
    # Let's query table constraints
    sql = """
    SELECT 
        tc.table_name, 
        tc.constraint_name, 
        tc.constraint_type,
        kcu.column_name
    FROM 
        information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu 
          ON tc.constraint_name = kcu.constraint_name
          AND tc.table_schema = kcu.table_schema
    WHERE 
        tc.table_schema = 'public' 
        AND tc.table_name IN ('orders', 'order_items', 'order_item_modifiers', 'inventory_transactions')
    ORDER BY 
        tc.table_name, tc.constraint_name, kcu.ordinal_position;
    """
    
    constraints = query_sql(sql)
    if constraints:
        print("=== Constraints ===")
        for c in constraints:
            print(c)
            
if __name__ == "__main__":
    main()
