// api.js
// AlphaPos — Modern Modular Web API Service
// This separates backend REST/Supabase interaction from UI rendering.

const BASE_URL = import.meta.env.VITE_SUPABASE_URL || 'http://127.0.0.1:54321/rest/v1';
const ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY || 'your-anon-key';

const defaultHeaders = {
  'Content-Type': 'application/json',
  'apikey': ANON_KEY,
  'Authorization': `Bearer ${ANON_KEY}`
};

/**
 * Perform secure HTTP fetch request.
 */
async function request(endpoint, options = {}) {
  const url = `${BASE_URL}${endpoint}`;
  const response = await fetch(url, {
    ...options,
    headers: {
      ...defaultHeaders,
      ...options.headers,
    },
  });

  if (!response.ok) {
    const errorData = await response.json().catch(() => ({}));
    throw new Error(errorData.message || `Request failed with status ${response.status}`);
  }

  return response.status === 204 ? null : response.json();
}

export const APIService = {
  /**
   * Fetch active menu items for a merchant.
   */
  async getMenuItems(merchantId) {
    return request(`/menu_items?merchant_id=eq.${merchantId}&is_available=eq.true&is_deleted=eq.false`);
  },

  /**
   * Submit client feedback rating for an order.
   */
  async submitFeedback(feedbackData) {
    return request('/customer_feedback', {
      method: 'POST',
      body: JSON.stringify(feedbackData),
    });
  },

  async completeCheckout() {
    const error = new Error('Customer checkout is staff-authorized and cannot be completed from the web client.');
    error.code = 'CUSTOMER_CHECKOUT_FORBIDDEN';
    throw error;
  }
};
