import sys
import json
import urllib.request
import urllib.error

# Ensure stdout is unbuffered so messages are flushed immediately
sys.stdout.reconfigure(line_buffering=True)

def main():
    url = "http://119.59.99.163:54323/api/mcp"
    headers = {
        "Content-Type": "application/json",
        "Accept": "text/event-stream, application/json"
    }
    
    while True:
        line = sys.stdin.readline()
        if not line:
            break
        
        line = line.strip()
        if not line:
            continue
            
        try:
            payload = json.loads(line)
            data = json.dumps(payload).encode('utf-8')
            
            req = urllib.request.Request(url, data=data, headers=headers, method="POST")
            try:
                with urllib.request.urlopen(req) as response:
                    res_body = response.read().decode('utf-8').strip()
                    if res_body:
                        sys.stdout.write(res_body + "\n")
                        sys.stdout.flush()
            except urllib.error.HTTPError as e:
                err_res = {
                    "jsonrpc": "2.0",
                    "id": payload.get("id"),
                    "error": {
                        "code": -32000 - e.code,
                        "message": f"HTTP Error {e.code}: {e.reason}"
                    }
                }
                sys.stdout.write(json.dumps(err_res) + "\n")
                sys.stdout.flush()
            except Exception as e:
                err_res = {
                    "jsonrpc": "2.0",
                    "id": payload.get("id"),
                    "error": {
                        "code": -32603,
                        "message": f"Proxy Connection Error: {str(e)}"
                    }
                }
                sys.stdout.write(json.dumps(err_res) + "\n")
                sys.stdout.flush()
        except Exception:
            pass

if __name__ == "__main__":
    main()
