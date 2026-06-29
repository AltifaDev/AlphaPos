/**
 * AlphaPos — Stock Receipt / Delivery Note Parser (Edge Function)
 *
 * Accepts up to 5 document images (base64 JSON)
 * and uses Google Gemini Vision API to extract item names, quantities,
 * units, and unit costs from the delivery notes / purchase invoices.
 *
 * Environment Variables (set via `supabase secrets set`):
 *   GEMINI_API_KEY — Google AI Studio API key
 */

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface GeminiPart {
  text?: string;
  inline_data?: {
    mime_type: string;
    data: string;
  };
}

interface ExtractedReceiptItem {
  name: string;
  quantity: number;
  unit: string | null;
  unit_cost: number;
}

interface ReceiptParseResult {
  items: ExtractedReceiptItem[];
  total_items_found: number;
  confidence: number;
}

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
    const geminiApiKey = Deno.env.get("GEMINI_API_KEY") || req.headers.get("x-gemini-api-key") || req.headers.get("X-Gemini-API-Key");
    if (!geminiApiKey) {
      return new Response(
        JSON.stringify({ 
          error: "GEMINI_API_KEY_MISSING",
          message: "Please configure GEMINI_API_KEY in Supabase secrets or provide it in the X-Gemini-API-Key header." 
        }),
        {
          status: 400,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }

    const body = await req.json();
    const images: string[] = body.images;

    if (!images || !Array.isArray(images) || images.length === 0) {
      return new Response(
        JSON.stringify({ error: "No images provided. Send { images: [base64String, ...] }" }),
        {
          status: 400,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }

    const prompt = buildReceiptExtractionPrompt();
    const parts: GeminiPart[] = [{ text: prompt }];

    for (const imageBase64 of images) {
      let mimeType = "image/jpeg";
      let cleanBase64 = imageBase64;

      if (imageBase64.startsWith("data:")) {
        const match = imageBase64.match(/^data:([^;]+);base64,(.+)$/);
        if (match) {
          mimeType = match[1];
          cleanBase64 = match[2];
        }
      }

      parts.push({
        inline_data: {
          mime_type: mimeType,
          data: cleanBase64,
        },
      });
    }

    const geminiResponse = await callGeminiVision(geminiApiKey, parts);
    const result = parseGeminiResponse(geminiResponse);

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

function buildReceiptExtractionPrompt(): string {
  return `You are an expert purchase receipt and delivery note analyzer for a restaurant inventory system.
Analyze the provided receipt/invoice/delivery note image(s) and extract the itemized products received.

RULES:
1. Identify all inventory/raw material items received.
2. For each item, extract:
   - name: The item name in its original language (e.g., "นมสด Meiji", "ถุงหิ้วกาแฟ", "Chair").
   - quantity: The numerical quantity received. Ensure it is parsed as a number (e.g. 5.0).
   - unit: The unit of measurement (e.g. "kg", "pcs", "bags", "packs", "bottles", "box") or null if not specified.
   - unit_cost: The cost price per single unit of the item. If not directly specified, calculate it by dividing the total item cost by its quantity.
3. Skip VAT lines, grand total lines, and vendor/customer addresses.
4. If the receipt has handwriting indicating quantities or unit costs, prioritize those additions.

OUTPUT FORMAT (strict JSON, no markdown):
{
  "items": [
    {
      "name": "Original Name",
      "quantity": 10.0,
      "unit": "kg",
      "unit_cost": 150.0
    }
  ],
  "total_items_found": 1,
  "confidence": 0.95
}

CONFIDENCE SCORING:
- 0.95-1.0: Clean print invoice, clear numbers and text.
- 0.80-0.94: Readable photo but some hand-written or blurred text.
- Below 0.80: Low quality image, text hard to read.

IMPORTANT: Return ONLY the JSON object, no additional text or markdown formatting.`;
}

async function callGeminiVision(apiKey: string, parts: GeminiPart[]): Promise<string> {
  const model = "gemini-2.0-flash";
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;

  const requestBody = {
    contents: [
      {
        parts: parts,
      },
    ],
    generationConfig: {
      temperature: 0.1,
      topP: 0.8,
      maxOutputTokens: 8192,
      responseMimeType: "application/json",
    },
    safetySettings: [
      { category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_NONE" },
      { category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_NONE" },
      { category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_NONE" },
      { category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_NONE" },
    ],
  };

  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(requestBody),
  });

  if (!response.ok) {
    const errorBody = await response.text();
    console.error("Gemini API error:", response.status, errorBody);
    throw new Error(`Gemini API error (${response.status}): ${errorBody}`);
  }

  const data = await response.json();
  const candidates = data?.candidates;
  if (!candidates || candidates.length === 0) {
    throw new Error("No response from Gemini API");
  }

  const content = candidates[0]?.content?.parts?.[0]?.text;
  if (!content) {
    throw new Error("Empty content from Gemini API");
  }

  return content;
}

function parseGeminiResponse(rawResponse: string): ReceiptParseResult {
  let jsonStr = rawResponse.trim();
  if (jsonStr.startsWith("```json")) {
    jsonStr = jsonStr.slice(7);
  } else if (jsonStr.startsWith("```")) {
    jsonStr = jsonStr.slice(3);
  }
  if (jsonStr.endsWith("```")) {
    jsonStr = jsonStr.slice(0, -3);
  }
  jsonStr = jsonStr.trim();

  try {
    const parsed = JSON.parse(jsonStr);

    const items: ExtractedReceiptItem[] = (parsed.items || [])
      .filter((item: Record<string, unknown>) => item.name && typeof item.quantity === "number")
      .map((item: Record<string, unknown>) => ({
        name: String(item.name).trim(),
        quantity: Number(item.quantity),
        unit: item.unit ? String(item.unit).trim() : null,
        unit_cost: typeof item.unit_cost === "number" ? Number(item.unit_cost) : 0.0,
      }));

    return {
      items,
      total_items_found: items.length,
      confidence: typeof parsed.confidence === "number" ? parsed.confidence : 0.8,
    };
  } catch (parseError) {
    console.error("Failed to parse Gemini response:", parseError, "Raw:", jsonStr.substring(0, 500));
    throw new Error("Failed to parse receipt details. Please ensure the receipt is clear and try again.");
  }
}
