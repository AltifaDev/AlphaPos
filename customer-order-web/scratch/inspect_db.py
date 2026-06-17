import json
import urllib.request
import urllib.parse

url = 'https://your-supabase-project.supabase.co'
key = 'your-anon-key'
merchant_id = 'your-merchant-uuid'

headers = {
    'apikey': key,
    'Authorization': f'Bearer {key}',
    'x-merchant-id': merchant_id
}

def query_table(path, params):
    query_str = urllib.parse.urlencode(params)
    req = urllib.request.Request(f"{url}/rest/v1/{path}?{query_str}", headers=headers)
    try:
        with urllib.request.urlopen(req) as res:
            return json.loads(res.read().decode())
    except Exception as e:
        print(f"Error querying {path}: {e}")
        return None

print("=== ALL TABLE SESSIONS ===")
sessions = query_table('table_sessions', {})
print(json.dumps(sessions, indent=2))

print("\n=== SEARCHING FOR 527F78 ===")
for s in sessions:
    if "527" in str(s) or "527F78" in str(s).upper():
        print("MATCHED SESSION:", s)
