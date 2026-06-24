const http = require('http');
const readline = require('readline');

const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    terminal: false
});

rl.on('line', (line) => {
    if (!line.trim()) return;
    try {
        const payload = JSON.parse(line);
        const data = JSON.stringify(payload);
        
        const req = http.request({
            hostname: '119.59.99.163',
            port: 54323,
            path: '/api/mcp',
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(data),
                'Accept': 'text/event-stream, application/json'
            }
        }, (res) => {
            let body = '';
            res.on('data', (chunk) => body += chunk);
            res.on('end', () => {
                if (body.trim()) {
                    console.log(body.trim());
                }
            });
        });
        
        req.on('error', (e) => {
            console.log(JSON.stringify({
                jsonrpc: '2.0',
                id: payload.id || null,
                error: {
                    code: -32603,
                    message: `Proxy Error: ${e.message}`
                }
            }));
        });
        
        req.write(data);
        req.end();
    } catch (err) {
        // Ignore JSON parsing errors
    }
});
