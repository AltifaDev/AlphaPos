/**
 * AlphaPos — Stock Receipt / Delivery Note Parser (Edge Function)
 *
 * Accepts up to 5 document images (base64 JSON)
 * and uses a Vision AI provider to extract item names, quantities,
 * units, and unit costs from delivery notes / purchase invoices.
 *
 * ── Provider Resolution (in order) ────────────────────────────────────────
 *  Request header  x-ai-provider    → overrides everything
 *  Request header  x-ai-api-key     → API key for above provider
 *
 *  Fallback chain (if no provider header):
 *    1. OPENROUTER_API_KEY  env / x-openrouter-api-key header  → OpenRouter
 *    2. GEMINI_API_KEY      env / x-gemini-api-key header      → Gemini Flash (free)
 *    3. OPENAI_API_KEY      env / x-openai-api-key header      → OpenAI GPT-4o
 *
 *  Environment Variables (Supabase Secrets):
 *    OPENROUTER_API_KEY  — OpenRouter key  (sk-or-v1-...)
 *    OPENROUTER_MODEL    — Model override  (default: openrouter/free)
 *    GEMINI_API_KEY      — Google Gemini key (AIza...)
 *    GEMINI_MODEL        — Gemini model override (default: gemini-2.0-flash)
 *    OPENAI_API_KEY      — OpenAI key (sk-...)
 *    OPENAI_MODEL        — OpenAI model override (default: gpt-4o-mini)
 */

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": [
    "authorization", "x-client-info", "apikey", "content-type",
    "x-ai-provider", "x-ai-api-key",
    "x-openrouter-api-key", "x-gemini-api-key", "x-openai-api-key",
  ].join(", "),
};

// ── Data Types ──────────────────────────────────────────────────────────────

interface ExtractedReceiptItem {
  line_number: string | null;
  seller_item_id: string | null;
  barcode: string | null;
  name: string;
  quantity: number;
  unit: string | null;
  unit_code: string | null;
  price_base_quantity: number;
  unit_cost: number;
  line_net_amount: number | null;
  vat_rate: number | null;
  vat_code: string | null;
  tax_amount: number | null;
  line_total: number | null;
  expiry_date: string | null;
  lot_number: string | null;
  confidence: number;
}

interface ReceiptParseResult {
  document_type: string;
  invoice_number: string | null;
  tax_invoice_number: string | null;
  po_number: string | null;
  supplier_name: string | null;
  supplier_tax_id: string | null;
  supplier_branch_code: string | null;
  customer_reference: string | null;
  invoice_date: string | null;
  order_date: string | null;
  delivery_date: string | null;
  currency_code: string;
  subtotal: number | null;
  tax_amount: number | null;
  grand_total: number | null;
  items: ExtractedReceiptItem[];
  total_items_found: number;
  confidence: number;
  validation_warnings: string[];
  // Meta fields (not in original — helps client show which provider was used)
  _provider?: string;
}

type AIProvider = "openrouter" | "gemini" | "openai";

// ── Main Handler ────────────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  try {
    // ── Resolve Provider & API Key ──────────────────────────────────────────
    const explicitProvider = req.headers.get("x-ai-provider") as AIProvider | null;
    const explicitApiKey   = req.headers.get("x-ai-api-key");

    let provider: AIProvider;
    let apiKey: string;

    if (explicitProvider && explicitApiKey) {
      // Client specified both provider + key
      provider = explicitProvider;
      apiKey   = explicitApiKey;
    } else {
      // Auto-detect from env/headers — first available wins
      const openrouterKey = Deno.env.get("OPENROUTER_API_KEY") || req.headers.get("x-openrouter-api-key");
      const geminiKey     = Deno.env.get("GEMINI_API_KEY")     || req.headers.get("x-gemini-api-key");
      const openaiKey     = Deno.env.get("OPENAI_API_KEY")     || req.headers.get("x-openai-api-key");

      if (openrouterKey) {
        provider = "openrouter"; apiKey = openrouterKey;
      } else if (geminiKey) {
        provider = "gemini"; apiKey = geminiKey;
      } else if (openaiKey) {
        provider = "openai"; apiKey = openaiKey;
      } else {
        return new Response(
          JSON.stringify({
            error: "NO_API_KEY",
            message: "ไม่พบ API Key กรุณาตั้งค่า provider ใน AI Settings หรือตั้ง OPENROUTER_API_KEY / GEMINI_API_KEY / OPENAI_API_KEY ใน Supabase Secrets",
          }),
          { status: 400, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
        );
      }
    }

    // ── Parse Request Body ──────────────────────────────────────────────────
    const contentType = req.headers.get("content-type")?.toLowerCase() ?? "";
    let images: string[] = [];

    if (contentType.startsWith("multipart/form-data")) {
      const formData = await req.formData();
      for (const part of formData.getAll("images")) {
        if (typeof part !== "string") {
          const arrayBuffer = await part.arrayBuffer();
          images.push(arrayBufferToBase64(arrayBuffer));
        } else {
          images.push(part);
        }
      }
    } else {
      const body = await req.json();
      images = body.images;
    }

    if (!images || !Array.isArray(images) || images.length === 0) {
      return new Response(
        JSON.stringify({ error: "No images provided. Send { images: [base64String, ...] } or multipart/form-data with images fields" }),
        { status: 400, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
      );
    }

    if (images.length > 5) {
      return new Response(
        JSON.stringify({ error: "Maximum 5 images allowed per request" }),
        { status: 400, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
      );
    }

    // ── Build Vision Content ────────────────────────────────────────────────
    const prompt = buildReceiptExtractionPrompt();
    const imagePayloads: Array<{ mimeType: string; cleanBase64: string }> = [];

    for (const imageBase64 of images) {
      let mimeType = "image/jpeg";
      let cleanBase64 = imageBase64;
      if (imageBase64.startsWith("data:")) {
        const match = imageBase64.match(/^data:([^;]+);base64,(.+)$/);
        if (match) { mimeType = match[1]; cleanBase64 = match[2]; }
      }
      imagePayloads.push({ mimeType, cleanBase64 });
    }

    // ── Call Provider with Auto-Fallback ────────────────────────────────────
    let rawResponse: string;
    let usedProvider = provider;

    try {
      rawResponse = await callProvider(provider, apiKey, prompt, imagePayloads);
    } catch (primaryError) {
      // On quota/rate-limit errors try next provider in chain
      const errMsg = primaryError instanceof Error ? primaryError.message : String(primaryError);
      const isQuotaError = /429|quota|rate.?limit|free.?tier|limit.?exceed/i.test(errMsg);

      if (isQuotaError) {
        // Try Gemini fallback if primary was OpenRouter
        const geminiKey = Deno.env.get("GEMINI_API_KEY") || req.headers.get("x-gemini-api-key");
        const openaiKey = Deno.env.get("OPENAI_API_KEY") || req.headers.get("x-openai-api-key");

        let fallbackKey: string | null = null;
        let fallbackProvider: AIProvider | null = null;

        if (provider !== "gemini" && geminiKey) {
          fallbackProvider = "gemini"; fallbackKey = geminiKey;
        } else if (provider !== "openai" && openaiKey) {
          fallbackProvider = "openai"; fallbackKey = openaiKey;
        }

        if (fallbackProvider && fallbackKey) {
          console.warn(`Primary provider ${provider} quota exceeded — falling back to ${fallbackProvider}`);
          rawResponse = await callProvider(fallbackProvider, fallbackKey, prompt, imagePayloads);
          usedProvider = fallbackProvider;
        } else {
          throw primaryError;
        }
      } else {
        throw primaryError;
      }
    }

    const result: ReceiptParseResult = parseAIResponse(rawResponse);
    result._provider = usedProvider;

    return new Response(JSON.stringify(result), {
      status: 200,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });

  } catch (error) {
    console.error("parse-stock-receipt error:", error);
    const message = error instanceof Error ? error.message : "Internal server error";
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }
});

// ── Provider Dispatcher ─────────────────────────────────────────────────────

async function callProvider(
  provider: AIProvider,
  apiKey: string,
  prompt: string,
  images: Array<{ mimeType: string; cleanBase64: string }>,
): Promise<string> {
  switch (provider) {
    case "openrouter": return await callOpenRouter(apiKey, prompt, images);
    case "gemini":     return await callGemini(apiKey, prompt, images);
    case "openai":     return await callOpenAI(apiKey, prompt, images);
    default:           throw new Error(`Unknown AI provider: ${provider}`);
  }
}

// ── OpenRouter ──────────────────────────────────────────────────────────────

async function callOpenRouter(
  apiKey: string,
  prompt: string,
  images: Array<{ mimeType: string; cleanBase64: string }>,
): Promise<string> {
  const configuredModel = Deno.env.get("OPENROUTER_MODEL") || "openrouter/free";
  const models = configuredModel === "openrouter/free"
    ? [configuredModel]
    : [configuredModel, "openrouter/free"];

  const content: Array<Record<string, unknown>> = [{ type: "text", text: prompt }];
  for (const img of images) {
    content.push({
      type: "image_url",
      image_url: { url: `data:${img.mimeType};base64,${img.cleanBase64}` },
    });
  }

  let lastError = "No OpenRouter model returned content";

  for (const model of models) {
    try {
      const response = await fetchWithTimeout("https://openrouter.ai/api/v1/chat/completions", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${apiKey}`,
          "Content-Type": "application/json",
          "HTTP-Referer": "https://alphapos.app",
          "X-Title": "AlphaPos Document Scanner",
        },
        body: JSON.stringify({
          model,
          messages: [
            { role: "system", content: "Extract structured document data. Return exactly one valid JSON object and no safety label, explanation, or markdown." },
            { role: "user", content },
          ],
          response_format: { type: "json_object" },
          reasoning: { effort: "low", exclude: true },
          temperature: 0.1,
          max_tokens: 8192,
        }),
      }, 75_000);

      if (!response.ok) {
        const errorBody = await response.text();
        lastError = `OpenRouter API error (${response.status}): ${errorBody}`;
        // Propagate 429 so caller can trigger fallback
        if (response.status === 429) throw new Error(lastError);
        console.error(lastError);
        continue;
      }

      const data = await response.json();
      const messageContent = data?.choices?.[0]?.message?.content;
      const text = typeof messageContent === "string"
        ? messageContent
        : Array.isArray(messageContent)
          ? messageContent.map((p: { text?: string }) => p.text || "").join("")
          : "";
      if (text.trim()) return text;
      lastError = `OpenRouter model ${model} returned empty content`;
      console.error(lastError, { model: data?.model, finish: data?.choices?.[0]?.finish_reason });
    } catch (err) {
      lastError = err instanceof Error ? err.message : String(err);
      if (/429|quota|rate/i.test(lastError)) throw new Error(lastError);
      console.error(`OpenRouter model ${model} failed:`, lastError);
    }
  }
  throw new Error(lastError);
}

// ── Google Gemini ───────────────────────────────────────────────────────────

async function callGemini(
  apiKey: string,
  prompt: string,
  images: Array<{ mimeType: string; cleanBase64: string }>,
): Promise<string> {
  const model = Deno.env.get("GEMINI_MODEL") || "gemini-2.0-flash";
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;

  const parts: Array<Record<string, unknown>> = [{ text: prompt }];
  for (const img of images) {
    parts.push({ inline_data: { mime_type: img.mimeType, data: img.cleanBase64 } });
  }

  const response = await fetchWithTimeout(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ parts }],
      generationConfig: {
        response_mime_type: "application/json",
        temperature: 0.1,
        maxOutputTokens: 8192,
      },
      systemInstruction: {
        parts: [{ text: "Extract structured document data. Return exactly one valid JSON object and no safety label, explanation, or markdown." }],
      },
    }),
  }, 75_000);

  if (!response.ok) {
    const errorBody = await response.text();
    const msg = `Gemini API error (${response.status}): ${errorBody}`;
    if (response.status === 429) throw new Error(`429 quota: ${msg}`);
    throw new Error(msg);
  }

  const data = await response.json();
  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text?.trim()) throw new Error("Gemini returned empty response");
  return text;
}

// ── OpenAI ──────────────────────────────────────────────────────────────────

async function callOpenAI(
  apiKey: string,
  prompt: string,
  images: Array<{ mimeType: string; cleanBase64: string }>,
): Promise<string> {
  const model = Deno.env.get("OPENAI_MODEL") || "gpt-4o-mini";

  const content: Array<Record<string, unknown>> = [{ type: "text", text: prompt }];
  for (const img of images) {
    content.push({
      type: "image_url",
      image_url: { url: `data:${img.mimeType};base64,${img.cleanBase64}`, detail: "high" },
    });
  }

  const response = await fetchWithTimeout("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model,
      messages: [
        { role: "system", content: "Extract structured document data. Return exactly one valid JSON object and no safety label, explanation, or markdown." },
        { role: "user", content },
      ],
      response_format: { type: "json_object" },
      temperature: 0.1,
      max_tokens: 8192,
    }),
  }, 75_000);

  if (!response.ok) {
    const errorBody = await response.text();
    const msg = `OpenAI API error (${response.status}): ${errorBody}`;
    if (response.status === 429) throw new Error(`429 quota: ${msg}`);
    throw new Error(msg);
  }

  const data = await response.json();
  const text = data?.choices?.[0]?.message?.content;
  if (!text?.trim()) throw new Error("OpenAI returned empty response");
  return text;
}

// ── Prompt ──────────────────────────────────────────────────────────────────

function buildReceiptExtractionPrompt(): string {
  return `You extract purchase invoices, tax invoices, receipts, and delivery notes into a Peppol/UBL-inspired JSON record.
Read every provided image as a page of ONE document. Extract each printed item row exactly once.

DOCUMENT RULES:
1. Never use customer number, member number, tax ID, order number, or purchase order as invoice_number.
2. For Thai documents, prefer labels in this order for invoice_number:
   "เลขที่ใบกำกับภาษี / Tax Invoice No." > "Invoice No." > "Receipt No.".
3. Keep purchase_order_number separate in po_number. Keep customer number in customer_reference.
4. Dates must be Gregorian ISO 8601 YYYY-MM-DD. For DD/MM/YYYY, the first component is day. Convert Buddhist year to Gregorian only when year >= 2400 by subtracting 543. Never invent a date.
5. If the document says page 1 of 1, do not infer additional pages or repeat rows.
6. Currency must be ISO 4217 (THB for documents stating บาท). Amounts are decimal numbers without separators.

LINE RULES:
1. Extract only rows in the item table. Do not treat totals, VAT summary, addresses, or document metadata as items.
2. Preserve line_number and seller_item_id/article number. These identify a line and product separately.
3. Transcribe name literally, character-for-character, from the DESCRIPTION cell on the same row as seller_item_id. Do not autocorrect, translate, expand abbreviations, or substitute a familiar product name. Re-check the name against the image before answering; lower confidence if any character is unclear.
4. quantity, unit, unit price, VAT rate/code, and printed line total must come from the same row.
5. unit_cost is the printed net unit price. price_base_quantity defaults to 1.
6. line_net_amount is quantity * unit_cost when the document does not print a different net amount.
7. Never duplicate a line. If the same page/image appears twice, emit each physical line only once.
8. expiry_date and lot_number must be null unless explicitly printed for that item. Never use today's date.
9. Use null for unreadable optional values and add a short validation_warnings entry instead of guessing.

OUTPUT FORMAT (strict JSON, no markdown):
{
  "document_type": "tax_invoice_receipt",
  "invoice_number": "033751007931",
  "tax_invoice_number": "033751007931",
  "po_number": "9150157906",
  "supplier_name": "บริษัท ซีพี แอ็กซ์ตร้า จำกัด (มหาชน)",
  "supplier_tax_id": "0107537000521",
  "supplier_branch_code": "00049",
  "customer_reference": "033059224000310",
  "invoice_date": "2023-06-20",
  "order_date": "2023-06-19",
  "delivery_date": null,
  "currency_code": "THB",
  "subtotal": 10260.00,
  "tax_amount": null,
  "grand_total": null,
  "items": [
    {
      "line_number": "1",
      "seller_item_id": "153761",
      "barcode": null,
      "name": "ซีเอชจัมโบ้ 35 ซม. * 1 แผ่น",
      "quantity": 12,
      "unit": "EA",
      "unit_code": "EA",
      "price_base_quantity": 1,
      "unit_cost": 345.00,
      "line_net_amount": 4140.00,
      "vat_rate": 7,
      "vat_code": "S",
      "tax_amount": null,
      "line_total": 4140.00,
      "expiry_date": null,
      "lot_number": null,
      "confidence": 0.98
    }
  ],
  "total_items_found": 1,
  "confidence": 0.95,
  "validation_warnings": []
}

IMPORTANT: Return ONLY the JSON object, no additional text or markdown formatting.`;
}

// ── Utilities ────────────────────────────────────────────────────────────────

function arrayBufferToBase64(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  const chunkSize = 8192;
  let binary = "";
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
}

async function fetchWithTimeout(url: string, init: RequestInit, timeoutMs: number): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

function parseAIResponse(rawResponse: string): ReceiptParseResult {
  let jsonStr = rawResponse.trim();

  // Strip markdown fences if present
  const fenceMatch = jsonStr.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
  if (fenceMatch) jsonStr = fenceMatch[1].trim();

  // Extract first JSON object
  const objMatch = jsonStr.match(/\{[\s\S]*\}/);
  if (objMatch) jsonStr = objMatch[0];

  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(jsonStr);
  } catch {
    throw new Error(`Failed to parse AI JSON response: ${jsonStr.substring(0, 300)}`);
  }

  const items: ExtractedReceiptItem[] = [];
  if (Array.isArray(parsed.items)) {
    for (const raw of parsed.items as Record<string, unknown>[]) {
      items.push({
        line_number:      String(raw.line_number ?? ""),
        seller_item_id:   (raw.seller_item_id as string) ?? null,
        barcode:          (raw.barcode as string) ?? null,
        name:             String(raw.name ?? ""),
        quantity:         Number(raw.quantity ?? 0),
        unit:             (raw.unit as string) ?? null,
        unit_code:        (raw.unit_code as string) ?? null,
        price_base_quantity: Number(raw.price_base_quantity ?? 1),
        unit_cost:        Number(raw.unit_cost ?? 0),
        line_net_amount:  raw.line_net_amount != null ? Number(raw.line_net_amount) : null,
        vat_rate:         raw.vat_rate != null ? Number(raw.vat_rate) : null,
        vat_code:         (raw.vat_code as string) ?? null,
        tax_amount:       raw.tax_amount != null ? Number(raw.tax_amount) : null,
        line_total:       raw.line_total != null ? Number(raw.line_total) : null,
        expiry_date:      (raw.expiry_date as string) ?? null,
        lot_number:       (raw.lot_number as string) ?? null,
        confidence:       Number(raw.confidence ?? 0.8),
      });
    }
  }

  return {
    document_type:       String(parsed.document_type ?? "unknown"),
    invoice_number:      (parsed.invoice_number as string) ?? null,
    tax_invoice_number:  (parsed.tax_invoice_number as string) ?? null,
    po_number:           (parsed.po_number as string) ?? null,
    supplier_name:       (parsed.supplier_name as string) ?? null,
    supplier_tax_id:     (parsed.supplier_tax_id as string) ?? null,
    supplier_branch_code:(parsed.supplier_branch_code as string) ?? null,
    customer_reference:  (parsed.customer_reference as string) ?? null,
    invoice_date:        (parsed.invoice_date as string) ?? null,
    order_date:          (parsed.order_date as string) ?? null,
    delivery_date:       (parsed.delivery_date as string) ?? null,
    currency_code:       String(parsed.currency_code ?? "THB"),
    subtotal:            parsed.subtotal != null ? Number(parsed.subtotal) : null,
    tax_amount:          parsed.tax_amount != null ? Number(parsed.tax_amount) : null,
    grand_total:         parsed.grand_total != null ? Number(parsed.grand_total) : null,
    items,
    total_items_found:   Number(parsed.total_items_found ?? items.length),
    confidence:          Number(parsed.confidence ?? 0.8),
    validation_warnings: Array.isArray(parsed.validation_warnings)
      ? (parsed.validation_warnings as string[])
      : [],
  };
}
