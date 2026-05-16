// USDA FoodData Central thin client. Used by the LLM as a tool, and as a
// last-resort lookup before falling back to a generic estimate.
//
// Key signup: https://fdc.nal.usda.gov/api-key-signup
// Docs: https://fdc.nal.usda.gov/api-guide

import type { Env } from "../types";

interface FdcSearchHit {
  fdcId: number;
  description: string;
  dataType: string;
  foodNutrients: Array<{
    nutrientName: string;
    nutrientNumber: string;
    value: number;
    unitName: string;
  }>;
  servingSize?: number;
  servingSizeUnit?: string;
}

export interface UsdaMacros {
  /** Per 100g unless servingGrams provided. */
  kcal: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
  /** USDA's best label for this food. */
  description: string;
  /** Grams in one serving as USDA defines it, or 100 by default. */
  servingGrams: number;
  fdcId: number;
}

/**
 * Search FDC for the best match for a free-text query and return per-100g
 * macros plus the canonical description. Returns null if no usable hit.
 */
export async function usdaSearch(query: string, env: Env, signal?: AbortSignal): Promise<UsdaMacros | null> {
  if (!env.USDA_FDC_API_KEY) return null;

  const url = new URL("https://api.nal.usda.gov/fdc/v1/foods/search");
  url.searchParams.set("api_key", env.USDA_FDC_API_KEY);
  url.searchParams.set("query", query);
  url.searchParams.set("pageSize", "3");
  // Foundation foods are the cleanest; Survey (FNDDS) gives "as eaten" prep.
  url.searchParams.set("dataType", "Foundation,SR Legacy,Survey (FNDDS)");

  const res = await fetch(url.toString(), { signal });
  if (!res.ok) return null;
  const data = (await res.json()) as { foods?: FdcSearchHit[] };
  const hit = data.foods?.[0];
  if (!hit) return null;

  const get = (numbers: string[]): number => {
    for (const num of numbers) {
      const n = hit.foodNutrients.find(x => x.nutrientNumber === num);
      if (n && typeof n.value === "number" && isFinite(n.value)) return n.value;
    }
    return 0;
  };

  // USDA nutrient numbers:
  //   208 Energy (kcal), 203 Protein, 205 Carbs, 204 Total fat
  // Energy alternates: 957 (Atwater, general), 268 (kJ → kcal at 0.239).
  const kcalDirect = get(["208", "957"]);
  const kj = get(["268"]);
  const kcal = kcalDirect > 0 ? kcalDirect : Math.round(kj * 0.239);

  // Treat zero-kcal hits as "no usable data". USDA sometimes returns rows
  // (e.g. water, raw spices) with kcal absent — surfacing them as a 0-cal
  // meal would silently log garbage. Return null so the caller falls through.
  if (kcal <= 0) return null;

  return {
    kcal,
    protein_g: get(["203"]),
    carbs_g: get(["205"]),
    fat_g: get(["204"]),
    description: hit.description,
    servingGrams: hit.servingSize ?? 100,
    fdcId: hit.fdcId
  };
}

/** Scale per-100g macros to a custom portion in grams. */
export function scaleUsda(macros: UsdaMacros, grams: number): Omit<UsdaMacros, "description" | "fdcId" | "servingGrams"> {
  const r = grams / 100;
  return {
    kcal: Math.round(macros.kcal * r),
    protein_g: Math.round(macros.protein_g * r),
    carbs_g: Math.round(macros.carbs_g * r),
    fat_g: Math.round(macros.fat_g * r)
  };
}
