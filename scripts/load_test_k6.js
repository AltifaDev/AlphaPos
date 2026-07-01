// load_test_k6.js
// AlphaPos — Pre-production Load/Performance Test Script (k6)
//
// To run this script:
//   1. Install k6 (macOS: `brew install k6`)
//   2. Run command: `k6 run scripts/load_test_k6.js`

import http from 'k6/http';
import { check, sleep } from 'k6';

// Define configuration options for the load test
export const options = {
    stages: [
        { duration: '30s', target: 20 },  // Ramp-up: from 0 to 20 virtual users (VUs) over 30s
        { duration: '1m', target: 50 },   // Stress: keep 50 users active for 1 minute (simulating peak sales)
        { duration: '30s', target: 0 },   // Ramp-down: scale back to 0 users over 30s
    ],
    thresholds: {
        http_req_duration: ['p(95)<500'], // 95% of requests must complete in under 500ms
        http_req_failed: ['rate<0.01'],   // Error rate must be less than 1%
    },
};

// Set fallback configs (can be overridden with environment variables)
const SUPABASE_URL = __ENV.SUPABASE_URL || 'https://your-project-id.supabase.co';
const SUPABASE_ANON_KEY = __ENV.SUPABASE_ANON_KEY || 'your-anon-key';

export default function () {
    const url = `${SUPABASE_URL}/rest/v1/rpc/complete_checkout`;
    
    // Simulate authorization headers and content-type
    const params = {
        headers: {
            'Content-Type': 'application/json',
            'apikey': SUPABASE_ANON_KEY,
            'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
        },
    };

    // Simulate mock order data payload
    const payload = JSON.stringify({
        p_merchant_id: '163350b0-056d-4d5e-b5d4-24e7aac5ab6d', // Default Local Merchant ID from seed
        p_order_id: '99999999-9999-9999-9999-' + Math.floor(Math.random() * 1000000000000).toString().padStart(12, '9'),
        p_payment_method: Math.random() > 0.5 ? 'cash' : 'promptpay',
        p_amount_paid: 120.00,
        p_items: [
            {
                product_id: '33333333-3333-3333-3333-333333333333',
                qty: 1,
                price: 120.00
            }
        ]
    });

    // Make the POST request to the Supabase Edge API / RPC
    const res = http.post(url, payload, params);

    // Verify response status
    check(res, {
        'status is 200 or 201': (r) => r.status === 200 || r.status === 201,
        'response time less than 500ms': (r) => r.timings.duration < 500,
    });

    // Simulate real user thinking time before next action (1 to 3 seconds)
    sleep(Math.random() * 2 + 1);
}
