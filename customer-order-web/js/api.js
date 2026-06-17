export async function fetchWithRetry(fn, maxRetries = 2) {
    let lastError;
    for (let attempt = 0; attempt <= maxRetries; attempt++) {
        try {
            return await fn();
        } catch (err) {
            lastError = err;
            if (attempt < maxRetries) {
                await new Promise(resolve => setTimeout(resolve, Math.pow(2, attempt) * 200));
            }
        }
    }
    throw lastError;
}

export async function fetchWithFallback({ supabase, supabaseKey, supabaseFn, localUrl, localOptions = {}, transform }) {
    let success = false;
    let result = null;

    if (supabase && supabaseKey) {
        try {
            result = await fetchWithRetry(supabaseFn);
            if (result != null) {
                if (transform) result = transform(result);
                success = true;
            }
        } catch (err) {
            console.warn("Supabase failed, trying local server:", err);
        }
    }

    if (!success && localUrl) {
        try {
            const res = await fetchWithRetry(async () => {
                const response = await fetch(localUrl, {
                    headers: { "Content-Type": "application/json" },
                    ...localOptions
                });
                if (!response.ok) throw new Error(`HTTP ${response.status}`);
                return response;
            });
            result = await (localOptions.parseJson !== false ? res.json() : res.text());
            if (transform) result = transform(result);
            success = true;
        } catch (err) {
            console.error("Local server also failed:", err);
        }
    }

    return { success, data: result };
}
