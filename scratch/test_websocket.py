import websocket
import json
import threading
import time
import sys

anonKey = "your-anon-key"
merchantId = "your-merchant-uuid"
wsURLString = f"wss://your-project-ref.supabase.co/realtime/v1/websocket?apikey={anonKey}&vsn=1.0.0"

def on_message(ws, message):
    try:
        data = json.loads(message)
        event = data.get("event")
        topic = data.get("topic")
        payload = data.get("payload", {})
        
        # Print event details
        print(f"\n[WS MESSAGE] Topic: {topic}, Event: {event}", flush=True)
        if event == "postgres_changes":
            data_payload = payload.get("data", {})
            table = data_payload.get("table")
            type_ = data_payload.get("type")
            record = data_payload.get("record") or data_payload.get("old_record") or {}
            print(f"  Table: {table}, Type: {type_}", flush=True)
            print(f"  Record: {json.dumps(record, indent=2)}", flush=True)
        else:
            print(f"  Payload: {json.dumps(payload, indent=2)}", flush=True)
    except Exception as e:
        print(f"Error parsing message: {e}\nRaw: {message}", flush=True)

def on_error(ws, error):
    print(f"WebSocket Error: {error}", flush=True)

def on_close(ws, close_status_code, close_msg):
    print(f"WebSocket Closed: status={close_status_code}, msg={close_msg}", flush=True)

def on_open(ws):
    print("WebSocket Connected! Sending join payload...", flush=True)
    
    join_payload = {
        "topic": "realtime:public",
        "event": "phx_join",
        "payload": {
            "config": {
                "postgres_changes": [
                    {"event": "*", "schema": "public", "table": "orders", "filter": f"merchant_id=eq.{merchantId}"},
                    {"event": "*", "schema": "public", "table": "order_items", "filter": f"merchant_id=eq.{merchantId}"},
                    {"event": "*", "schema": "public", "table": "service_requests", "filter": f"merchant_id=eq.{merchantId}"}
                ]
            }
        },
        "ref": "1"
    }
    
    ws.send(json.dumps(join_payload))
    
    # Heartbeat thread
    def send_heartbeat():
        while True:
            time.sleep(20)
            try:
                heartbeat = {
                    "topic": "phoenix",
                    "event": "heartbeat",
                    "payload": {},
                    "ref": "heartbeat"
                }
                ws.send(json.dumps(heartbeat))
                print("[WS SENT] Heartbeat", flush=True)
            except Exception as e:
                print(f"Failed to send heartbeat: {e}", flush=True)
                break
                
    t = threading.Thread(target=send_heartbeat, daemon=True)
    t.start()

if __name__ == "__main__":
    print(f"Connecting to: {wsURLString}", flush=True)
    websocket.enableTrace(False)
    ws = websocket.WebSocketApp(
        wsURLString,
        on_open=on_open,
        on_message=on_message,
        on_error=on_error,
        on_close=on_close
    )
    ws.run_forever()
