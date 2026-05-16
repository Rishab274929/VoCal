// GET /api/barcode/:code
//
// Looks up a UPC/EAN barcode against Open Food Facts (free, public, no key).
// Returns a `ParsedMeal`-shaped object the iOS app can drop straight into
// `VoiceParseResponse.ParsedMeal`. Falls back to a 404 if Open Food Facts
// doesn't know the code, so the client can prompt the user to add macros
// manually or via voice.
//
// Why Open Food Facts? It's the largest open, free, multilingual food
// database; covers ~3M products including most US/EU grocery items. Their
// `/api/v2/product/<code>.json` endpoint is unauthenticated and cacheable.

import type { PagesFunction } from "@cloudflare/workers-types";
import type { Env, ParsedMeal } from "../../../src/types";
import { guessSlot } from "../../../src/lib/normalize";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type"
};

interface OFFProduct {
  status: number;
  status_verbose?: string;
  product?: {
    code?: string;
    product_name?: string;
    product_name_en?: string;
    brands?: string;
    quantity?: string;
    serving_size?: string;
    serving_quantity?: string | number;
    nutriments?: {
      "energy-kcal_serving"?: number;
      "energy-kcal_100g"?: number;
      "proteins_serving"?: number;
      "proteins_100g"?: number;
      "carbohydrates_serving"?: number;
      "carbohydrates_100g"?: number;
      "fat_serving"?: number;
      "fat_100g"?: number;
    };
  };
}

export const onRequestOptions: PagesFunction<Env> = async () => {
  return new Response(null, { status: 204, headers: CORS });
};

export const onRequestGet: PagesFunction<Env> = async ({ params, env }) => {
  const raw = String(params.code ?? "").trim();
  // Open Food Facts accepts 8-14 digit codes (UPC-A, UPC-E, EAN-8, EAN-13, GTIN-14).
  if (!/^\d{8,14}$/.test(raw)) {
    return json({ error: "Invalid barcode format" }, 400);
  }

  // KV cache: barcodes don't change. 30-day TTL.
  if (env.FOOD_KV) {
    const cached = await env.FOOD_KV.get<ParsedMeal>(`barcode:${raw}`, "json").catch(() => null);
    if (cached) return json({ meal: cached, source: "cache" }, 200);
  }

  // Open Food Facts rejects Cloudflare Worker requests with 525, so we
  // try USDA FoodData Central's Branded dataset first (queryable by GTIN-UPC)
  // and fall back to OFF as a courtesy. USDA needs an API key; if the key
  // isn't configured we skip straight to OFF.
  let lastErr = "";

  // ---- USDA path ----
  if (env.USDA_FDC_API_KEY) {
    try {
      const usdaUrl = new URL("https://api.nal.usda.gov/fdc/v1/foods/search");
      usdaUrl.searchParams.set("api_key", env.USDA_FDC_API_KEY);
      usdaUrl.searchParams.set("query", raw);
      usdaUrl.searchParams.set("dataType", "Branded");
      usdaUrl.searchParams.set("pageSize", "1");
      const res = await fetch(usdaUrl.toString());
      if (res.ok) {
        const data = (await res.json()) as {
          foods?: Array<{
            description?: string;
            brandOwner?: string;
            brandName?: string;
            gtinUpc?: string;
            servingSize?: number;
            servingSizeUnit?: string;
            householdServingFullText?: string;
            foodNutrients?: Array<{ nutrientNumber?: string; value?: number }>;
          }>;
        };
        const hit = data.foods?.[0];
        if (hit && (hit.gtinUpc?.replace(/^0+/, "") === raw.replace(/^0+/, ""))) {
          const n = (num: string): number => {
            const f = hit.foodNutrients?.find(x => x.nutrientNumber === num);
            return typeof f?.value === "number" ? f.value : 0;
          };
          const servingG = hit.servingSize ?? 100;
          // USDA Branded reports per 100g; scale to one serving.
          const scale = servingG / 100;
          const meal: ParsedMeal = {
            name: [hit.brandName ?? hit.brandOwner, hit.description].filter(Boolean).join(" · ").slice(0, 80),
            detail: (hit.householdServingFullText ?? `${servingG}g`) + ` · barcode ${raw}`,
            kcal: Math.round(n("208") * scale),
            protein_g: Math.round(n("203") * scale),
            carbs_g: Math.round(n("205") * scale),
            fat_g: Math.round(n("204") * scale),
            slot: guessSlot(),
            source: "barcode",
            confidence: 0.92
          };
          if (meal.kcal > 0) {
            if (env.FOOD_KV) {
              await env.FOOD_KV.put(`barcode:${raw}`, JSON.stringify(meal), { expirationTtl: 60 * 60 * 24 * 30 }).catch(() => undefined);
            }
            return json({ meal, source: "usda-fdc-branded" }, 200);
          }
        }
      } else {
        lastErr = `USDA returned ${res.status}`;
      }
    } catch (err) {
      lastErr = `USDA fetch failed: ${(err as Error).message}`;
    }
  }

  // ---- Open Food Facts fallback ----
  let off: OFFProduct | undefined;
  const hosts = [
    `https://static.openfoodfacts.org/api/v0/product/${raw}.json`,
    `https://world.openfoodfacts.org/api/v0/product/${raw}.json`
  ];
  for (const url of hosts) {
    try {
      const res = await fetch(url, {
        headers: {
          "User-Agent": "VoCal/1.0 - https://vocal.best - hello@vocal.best",
          "Accept": "application/json"
        }
      });
      if (!res.ok) {
        lastErr = `OFF ${new URL(url).hostname} returned ${res.status}`;
        continue;
      }
      off = (await res.json()) as OFFProduct;
      if (off.status === 1) break;
    } catch (err) {
      lastErr = `OFF lookup failed: ${(err as Error).message}`;
    }
  }
  if (!off) {
    return json({ error: lastErr || "No barcode data source available", code: raw }, 502);
  }

  if (off.status !== 1 || !off.product) {
    return json({ error: "Barcode not found in Open Food Facts", code: raw }, 404);
  }

  const p = off.product;
  const n = p.nutriments ?? {};
  // Prefer per-serving nutrients. If not present, scale per-100g by
  // serving_quantity (grams). If neither is present, fall back to 100g.
  const servingG = typeof p.serving_quantity === "number"
    ? p.serving_quantity
    : Number(p.serving_quantity ?? 100);
  const scale = isFinite(servingG) && servingG > 0 ? servingG / 100 : 1;
  const pick = (perServing: number | undefined, per100: number | undefined): number => {
    if (typeof perServing === "number" && isFinite(perServing)) return perServing;
    if (typeof per100 === "number" && isFinite(per100)) return per100 * scale;
    return 0;
  };

  const kcal = pick(n["energy-kcal_serving"], n["energy-kcal_100g"]);
  if (kcal <= 0) {
    return json({ error: "Open Food Facts has no kcal data for this code", code: raw }, 404);
  }

  const name = [p.brands?.split(",")[0]?.trim(), p.product_name_en ?? p.product_name]
    .filter(Boolean)
    .join(" · ") || `Barcode ${raw}`;
  const detail = p.serving_size
    ? `${p.serving_size} · barcode ${raw}`
    : p.quantity
    ? `${p.quantity} · barcode ${raw}`
    : `Barcode ${raw}`;

  const meal: ParsedMeal = {
    name: name.slice(0, 80),
    detail: detail.slice(0, 120),
    kcal: Math.round(kcal),
    protein_g: Math.round(pick(n.proteins_serving, n.proteins_100g)),
    carbs_g: Math.round(pick(n.carbohydrates_serving, n.carbohydrates_100g)),
    fat_g: Math.round(pick(n.fat_serving, n.fat_100g)),
    slot: guessSlot(),
    source: "barcode",
    confidence: 0.93
  };

  if (env.FOOD_KV) {
    await env.FOOD_KV.put(`barcode:${raw}`, JSON.stringify(meal), { expirationTtl: 60 * 60 * 24 * 30 }).catch(() => undefined);
  }

  return json({ meal, source: "openfoodfacts" }, 200);
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS }
  });
}
