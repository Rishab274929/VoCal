// Restaurant chain canon. Curated subset of public nutrition data for the
// top QSR chains. The LLM can also reach for this via the lookup_chain tool,
// but most matches hit here directly before any LLM call.
//
// Numbers sourced from each chain's published nutrition guide. Where a
// quantity isn't obvious (e.g. "fries" without a size), we resolve to the
// medium / default option and surface the choice in `detail`.

import type { ParsedMeal } from "../types";

interface Item {
  /** Lowercased aliases that should match this item. ALL terms must appear. */
  match: string[][];
  /** Macros + optional micros. Sodium especially is well-published for
   *  QSR chains and is the most useful micronutrient to surface. */
  meal: Omit<ParsedMeal, "slot" | "source" | "confidence">;
  defaultSlot: ParsedMeal["slot"];
}

interface Chain {
  brand: string;
  matchBrand: string[];
  items: Item[];
}

export const CHAIN_CANON: Chain[] = [
  {
    brand: "McDonald's",
    matchBrand: ["mcdonald", "mcdonalds", "mcd"],
    items: [
      {
        match: [["fries", "large"], ["fry", "large"], ["large", "fr"]],
        meal: { name: "McDonald's French Fries (Large)", detail: "Chain menu match", kcal: 480, protein_g: 7, carbs_g: 66, fat_g: 23, sodium_mg: 400, fiber_g: 6, sugar_g: 0, potassium_mg: 800 },
        defaultSlot: "snack"
      },
      {
        match: [["fries", "small"], ["fry", "small"], ["small", "fr"]],
        meal: { name: "McDonald's French Fries (Small)", detail: "Chain menu match", kcal: 230, protein_g: 3, carbs_g: 31, fat_g: 11, sodium_mg: 190, fiber_g: 3, sugar_g: 0, potassium_mg: 380 },
        defaultSlot: "snack"
      },
      {
        match: [["fr", "med"], ["fries", "medium"], ["fries"], ["fry"]],
        meal: { name: "McDonald's French Fries (Medium)", detail: "Chain menu match", kcal: 320, protein_g: 4, carbs_g: 43, fat_g: 15, sodium_mg: 260, fiber_g: 4, sugar_g: 0, potassium_mg: 540 },
        defaultSlot: "snack"
      },
      {
        match: [["big", "mac"]],
        meal: { name: "McDonald's Big Mac", detail: "Chain menu match", kcal: 590, protein_g: 25, carbs_g: 45, fat_g: 34, sodium_mg: 1050, fiber_g: 3, sugar_g: 9, calcium_mg: 260, iron_mg: 4.5 },
        defaultSlot: "lunch"
      },
      {
        match: [["quarter", "pounder"]],
        meal: { name: "McDonald's Quarter Pounder with Cheese", detail: "Chain menu match", kcal: 520, protein_g: 30, carbs_g: 42, fat_g: 26, sodium_mg: 1140, fiber_g: 3, sugar_g: 10, calcium_mg: 320, iron_mg: 4.5 },
        defaultSlot: "lunch"
      },
      {
        match: [["mcchicken"], ["mc", "chicken"]],
        meal: { name: "McDonald's McChicken", detail: "Chain menu match", kcal: 400, protein_g: 14, carbs_g: 39, fat_g: 21, sodium_mg: 560, fiber_g: 2, sugar_g: 5 },
        defaultSlot: "lunch"
      },
      {
        match: [["mcnugget"], ["chicken", "nugget", "10"]],
        meal: { name: "McDonald's Chicken McNuggets (10 pc)", detail: "Chain menu match", kcal: 410, protein_g: 23, carbs_g: 25, fat_g: 24, sodium_mg: 900, fiber_g: 1, sugar_g: 0 },
        defaultSlot: "lunch"
      },
      {
        match: [["egg", "mcmuffin"], ["sausage", "mcmuffin"]],
        meal: { name: "McDonald's Egg McMuffin", detail: "Chain menu match", kcal: 310, protein_g: 17, carbs_g: 30, fat_g: 13, sodium_mg: 770, fiber_g: 2, sugar_g: 3, calcium_mg: 320, iron_mg: 2.7 },
        defaultSlot: "breakfast"
      }
    ]
  },
  {
    brand: "Starbucks",
    matchBrand: ["starbucks", "sbux"],
    items: [
      {
        match: [["iced", "oat", "latte"], ["iced", "oatmilk", "latte"]],
        meal: { name: "Starbucks Iced Oatmilk Latte (Grande)", detail: "Oatmilk", kcal: 190, protein_g: 3, carbs_g: 24, fat_g: 8 },
        defaultSlot: "breakfast"
      },
      {
        match: [["latte", "oat"], ["latte", "oatmilk"]],
        meal: { name: "Starbucks Oatmilk Latte (Grande)", detail: "Oatmilk", kcal: 270, protein_g: 4, carbs_g: 35, fat_g: 12 },
        defaultSlot: "breakfast"
      },
      {
        match: [["latte"]],
        meal: { name: "Starbucks Caffe Latte (Grande)", detail: "2% milk", kcal: 190, protein_g: 13, carbs_g: 18, fat_g: 7 },
        defaultSlot: "breakfast"
      },
      {
        match: [["pumpkin", "spice", "latte"], ["psl"]],
        meal: { name: "Starbucks Pumpkin Spice Latte (Grande)", detail: "2% milk, whipped cream", kcal: 390, protein_g: 14, carbs_g: 52, fat_g: 14 },
        defaultSlot: "breakfast"
      },
      {
        match: [["cold", "brew"]],
        meal: { name: "Starbucks Cold Brew (Grande)", detail: "Black", kcal: 5, protein_g: 1, carbs_g: 0, fat_g: 0 },
        defaultSlot: "breakfast"
      },
      {
        match: [["frappuccino"], ["frap"]],
        meal: { name: "Starbucks Caramel Frappuccino (Grande)", detail: "Whipped cream", kcal: 380, protein_g: 5, carbs_g: 56, fat_g: 15 },
        defaultSlot: "snack"
      }
    ]
  },
  {
    brand: "Chipotle",
    matchBrand: ["chipotle"],
    items: [
      // Bowls are handled specially below — they need the structured-ingredient flow.
    ]
  },
  {
    brand: "Chick-fil-A",
    matchBrand: ["chick-fil-a", "chickfila", "chick fil a"],
    items: [
      {
        match: [["chicken", "sandwich"]],
        meal: { name: "Chick-fil-A Chicken Sandwich", detail: "Original, no sides", kcal: 420, protein_g: 28, carbs_g: 41, fat_g: 17, sodium_mg: 1400, fiber_g: 1, sugar_g: 5 },
        defaultSlot: "lunch"
      },
      {
        match: [["spicy", "chicken", "sandwich"]],
        meal: { name: "Chick-fil-A Spicy Chicken Sandwich", detail: "No sides", kcal: 450, protein_g: 28, carbs_g: 41, fat_g: 20, sodium_mg: 1620, fiber_g: 1, sugar_g: 5 },
        defaultSlot: "lunch"
      },
      {
        match: [["grilled", "nugget", "12"]],
        meal: { name: "Chick-fil-A Grilled Nuggets (12 pc)", detail: "Lean", kcal: 210, protein_g: 38, carbs_g: 2, fat_g: 5, sodium_mg: 770, fiber_g: 0, sugar_g: 1 },
        defaultSlot: "lunch"
      },
      {
        match: [["nugget", "8"]],
        meal: { name: "Chick-fil-A Chicken Nuggets (8 pc)", detail: "Breaded", kcal: 250, protein_g: 27, carbs_g: 11, fat_g: 11, sodium_mg: 1210, fiber_g: 1, sugar_g: 1 },
        defaultSlot: "lunch"
      },
      {
        match: [["waffle", "fr"]],
        meal: { name: "Chick-fil-A Waffle Fries (Medium)", detail: "Side", kcal: 420, protein_g: 5, carbs_g: 50, fat_g: 24, sodium_mg: 280, fiber_g: 5, sugar_g: 0, potassium_mg: 880 },
        defaultSlot: "snack"
      }
    ]
  },
  {
    brand: "Burger King",
    matchBrand: ["burger king", "bk"],
    items: [
      {
        match: [["whopper"]],
        meal: { name: "Burger King Whopper", detail: "Chain menu match", kcal: 670, protein_g: 28, carbs_g: 49, fat_g: 40, sodium_mg: 980, fiber_g: 2, sugar_g: 11 },
        defaultSlot: "lunch"
      },
      {
        match: [["whopper", "jr"]],
        meal: { name: "Burger King Whopper Jr.", detail: "Chain menu match", kcal: 340, protein_g: 15, carbs_g: 29, fat_g: 19, sodium_mg: 580, fiber_g: 1, sugar_g: 7 },
        defaultSlot: "lunch"
      }
    ]
  },
  {
    brand: "Subway",
    matchBrand: ["subway"],
    items: [
      {
        match: [["turkey", "footlong"], ["footlong", "turkey"]],
        meal: { name: "Subway Turkey Footlong", detail: "9-grain wheat, standard veg", kcal: 560, protein_g: 36, carbs_g: 90, fat_g: 8, sodium_mg: 1820, fiber_g: 8, sugar_g: 12 },
        defaultSlot: "lunch"
      },
      {
        match: [["italian", "bmt"]],
        meal: { name: "Subway Italian B.M.T. (6 inch)", detail: "9-grain wheat", kcal: 420, protein_g: 19, carbs_g: 45, fat_g: 17, sodium_mg: 1300, fiber_g: 4, sugar_g: 7 },
        defaultSlot: "lunch"
      }
    ]
  },
  {
    brand: "Taco Bell",
    matchBrand: ["taco bell"],
    items: [
      {
        match: [["crunchwrap", "supreme"]],
        meal: { name: "Taco Bell Crunchwrap Supreme", detail: "Beef", kcal: 530, protein_g: 16, carbs_g: 71, fat_g: 21, sodium_mg: 1200, fiber_g: 6, sugar_g: 6 },
        defaultSlot: "lunch"
      },
      {
        match: [["crunchy", "taco"]],
        meal: { name: "Taco Bell Crunchy Taco", detail: "Beef", kcal: 170, protein_g: 8, carbs_g: 13, fat_g: 9, sodium_mg: 310, fiber_g: 3, sugar_g: 1 },
        defaultSlot: "snack"
      }
    ]
  }
];

/**
 * Try to match a transcript to a chain item. Returns null if no chain mentioned
 * or no item-level match within the chain.
 */
export function matchChain(transcript: string): ParsedMeal | null {
  const text = transcript.toLowerCase();
  const chain = CHAIN_CANON.find(c => c.matchBrand.some(b => text.includes(b)));
  if (!chain) return null;
  for (const item of chain.items) {
    if (item.match.some(group => group.every(tok => text.includes(tok)))) {
      return {
        ...item.meal,
        slot: item.defaultSlot,
        source: "voice",
        confidence: 0.95
      };
    }
  }
  return null;
}

/**
 * Parse a Chipotle bowl out of the transcript. Returns `followUp` when guac
 * is mentioned but the portion isn't specified; otherwise returns the meal.
 */
export function parseChipotleBowl(
  transcript: string,
  followUpAnswer: string | null | undefined
): { meal: ParsedMeal } | { followUp: string; reasoning: string } | null {
  const text = transcript.toLowerCase();
  if (!text.includes("chipotle") || !text.includes("bowl")) return null;
  const answer = (followUpAnswer ?? "").toLowerCase();
  const guacAnswered = answer.includes("single") || answer.includes("double") || answer.includes("two");

  if (text.includes("guac") && !guacAnswered) {
    return {
      followUp: "Single scoop of guac?",
      reasoning: "Need guac portion to finalize macros."
    };
  }

  const doubleChicken = text.includes("double") && text.includes("chicken");
  const chickenCals = doubleChicken ? 360 : 180;
  const chickenProtein = doubleChicken ? 64 : 32;
  const chickenFat = doubleChicken ? 14 : 7;
  const guacDouble = answer.includes("double") || answer.includes("two");
  const wantsGuac = text.includes("guac");
  const guacCals = wantsGuac ? (guacDouble ? 460 : 230) : 0;
  const guacFat = wantsGuac ? (guacDouble ? 44 : 22) : 0;
  const guacCarbs = wantsGuac ? (guacDouble ? 16 : 8) : 0;

  const kcal = 210 + 130 + chickenCals + guacCals;
  const detail = `${doubleChicken ? "double" : "single"} chicken, brown rice, black beans${wantsGuac ? `, ${guacDouble ? "2× guac" : "1× guac"}` : ""}`;

  return {
    meal: {
      name: "Chipotle Chicken Bowl",
      detail,
      kcal,
      protein_g: chickenProtein + 9,
      carbs_g: 45 + 22 + guacCarbs,
      fat_g: chickenFat + 2 + guacFat,
      slot: "lunch",
      source: "voice",
      confidence: 0.93
    }
  };
}
