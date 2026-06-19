/**
 * AlphaPos — Menu Image Parser (Edge Function)
 *
 * Accepts up to 5 menu images (multipart/form-data or base64 JSON)
 * and uses Google Gemini Vision API to extract product names, prices,
 * and suggested categories from the menu photos.
 *
 * Environment Variables (set via `supabase secrets set`):
 *   GEMINI_API_KEY — Google AI Studio API key
 *
 * Request:
 *   POST /parse-menu-image
 *   Content-Type: application/json
 *   Body: { "images": ["base64-encoded-image-1", ...] }
 *
 * Response (200):
 *   {
 *     "items": [
 *       { "name": "ข้าวผัดกุ้ง", "price": 120.0, "suggested_category": "Main Dishes" }
 *     ],
 *     "suggested_categories": ["Main Dishes", "Beverages"],
 *     "total_items_found": 25,
 *     "confidence": 0.92
 *   }
 */

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
  // Handle CORS preflight
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

    // Parse request body
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

    if (images.length > 5) {
      return new Response(
        JSON.stringify({ error: "Maximum 5 images allowed per request" }),
        {
          status: 400,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }

    // Build Gemini Vision API request
    const prompt = buildMenuExtractionPrompt();
    const parts: GeminiPart[] = [{ text: prompt }];

    for (const imageBase64 of images) {
      // Auto-detect MIME type from base64 header or default to JPEG
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

    // Call Gemini API
    const geminiResponse = await callGeminiVision(geminiApiKey, parts);

    // Parse the structured response
    const result = parseGeminiResponse(geminiResponse);

    return new Response(JSON.stringify(result), {
      status: 200,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("parse-menu-image error:", error);

    const message = error instanceof Error ? error.message : "Internal server error";
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }
});

// ── Types ──────────────────────────────────────────────────────────────

interface GeminiPart {
  text?: string;
  inline_data?: {
    mime_type: string;
    data: string;
  };
}

interface ExtractedItem {
  name: string;
  price: number;
  suggested_category: string | null;
  description: string | null;
}

interface ParseResult {
  items: ExtractedItem[];
  suggested_categories: string[];
  total_items_found: number;
  confidence: number;
}

// ── Prompt ─────────────────────────────────────────────────────────────

function buildMenuExtractionPrompt(): string {
  return `You are a professional menu data extractor for a restaurant POS system. 
Analyze the provided menu image(s) and extract ALL food/drink items with their prices.

RULES:
1. Extract every single menu item you can find — name and price are required.
2. Prices must be numeric (no currency symbols). If a price range is shown (e.g., "80-120"), use the first/lower price.
3. If the menu has categories/sections (e.g., "Appetizers", "Main Dishes", "Drinks"), include them as suggested_category.
4. Keep the original language for item names (Thai, English, or mixed). Do NOT translate them.
5. If an item has a brief description visible on the menu, include it.
6. If you find size variants (S/M/L, Small/Large), create separate entries with size in parentheses.
7. Skip decorative text, restaurant name, phone numbers, and non-menu content.

OUTPUT FORMAT (strict JSON, no markdown):
{
  "items": [
    {
      "name": "Item Name (original language)",
      "price": 120.0,
      "suggested_category": "Category Name or null",
      "description": "Brief description or null"
    }
  ],
  "suggested_categories": ["Category1", "Category2"],
  "total_items_found": 25,
  "confidence": 0.92
}

CONFIDENCE SCORING:
- 0.95-1.0: Clear, well-lit photo, all text readable
- 0.80-0.94: Mostly readable with some unclear items
- 0.60-0.79: Several items hard to read, low quality photo
- Below 0.60: Very poor quality, many guesses

IMPORTANT: Return ONLY the JSON object, no additional text or markdown formatting.`;
}

// ── Gemini API Call ────────────────────────────────────────────────────

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
      temperature: 0.1, // Low temperature for accurate extraction
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

  // Extract text from Gemini response
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

// ── Response Parser ───────────────────────────────────────────────────

function parseGeminiResponse(rawResponse: string): ParseResult {
  // Clean up possible markdown code block wrapping
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

    // Validate and normalize the response
    const items: ExtractedItem[] = (parsed.items || [])
      .filter((item: Record<string, unknown>) => item.name && typeof item.price === "number" && item.price > 0)
      .map((item: Record<string, unknown>) => ({
        name: String(item.name).trim(),
        price: Number(item.price),
        suggested_category: item.suggested_category ? String(item.suggested_category).trim() : null,
        description: item.description ? String(item.description).trim() : null,
      }));

    // Collect unique categories
    const categorySet = new Set<string>();
    for (const item of items) {
      if (item.suggested_category) {
        categorySet.add(item.suggested_category);
      }
    }

    return {
      items,
      suggested_categories: Array.from(categorySet),
      total_items_found: items.length,
      confidence: typeof parsed.confidence === "number" ? parsed.confidence : 0.8,
    };
  } catch (parseError) {
    console.error("Failed to parse Gemini response:", parseError, "Raw:", jsonStr.substring(0, 500));
    throw new Error("Failed to parse AI response. Please try again with a clearer image.");
  }
}
