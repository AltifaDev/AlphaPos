import Foundation

let anonKey = "your-anon-key"
let merchantId = "your-merchant-uuid"

let wsURLString = "wss://your-project-ref.supabase.co/realtime/v1/websocket?apikey=\(anonKey)&vsn=1.0.0"
guard let url = URL(string: wsURLString) else {
    print("Invalid URL")
    exit(1)
}

print("Connecting to \(url.absoluteString)...")
let session = URLSession(configuration: .default)
let task = session.webSocketTask(with: url)
task.resume()

func listen() {
    task.receive { result in
        switch result {
        case .success(let message):
            switch message {
            case .string(let text):
                print("\n[WS RECEIVED STRING]:\n\(text)")
            case .data(let data):
                if let text = String(data: data, encoding: .utf8) {
                    print("\n[WS RECEIVED DATA]:\n\(text)")
                } else {
                    print("\n[WS RECEIVED BINARY DATA]: \(data.count) bytes")
                }
            @unknown default:
                break
            }
            listen()
        case .failure(let error):
            print("WebSocket error: \(error)")
            exit(1)
        }
    }
}

// Start listening
listen()

// Send Join Payload
let joinPayload: [String: Any] = [
    "topic": "realtime:public",
    "event": "phx_join",
    "payload": [
        "config": [
            "postgres_changes": [
                ["event": "*", "schema": "public", "table": "orders", "filter": "merchant_id=eq.\(merchantId)"],
                ["event": "*", "schema": "public", "table": "order_items", "filter": "merchant_id=eq.\(merchantId)"],
                ["event": "*", "schema": "public", "table": "service_requests", "filter": "merchant_id=eq.\(merchantId)"]
            ]
        ]
    ],
    "ref": "1"
]

if let data = try? JSONSerialization.data(withJSONObject: joinPayload, options: []),
   let jsonString = String(data: data, encoding: .utf8) {
    print("Sending join payload...")
    task.send(.string(jsonString)) { error in
        if let error = error {
            print("Failed to send join payload: \(error)")
        } else {
            print("Join payload sent successfully!")
        }
    }
}

// Start heartbeat timer
let timer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { _ in
    let heartbeat: [String: Any] = [
        "topic": "phoenix",
        "event": "heartbeat",
        "payload": [:],
        "ref": "heartbeat"
    ]
    if let data = try? JSONSerialization.data(withJSONObject: heartbeat, options: []),
       let jsonString = String(data: data, encoding: .utf8) {
        task.send(.string(jsonString)) { error in
            if let error = error {
                print("Heartbeat failed: \(error)")
            } else {
                print("Heartbeat sent.")
            }
        }
    }
}

// Run the runloop to keep script alive
RunLoop.main.run()
