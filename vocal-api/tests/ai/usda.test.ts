import { describe, it, expect } from "vitest";
import { scaleUsda, type UsdaMacros } from "../../src/ai/usda";

const baseMacros: UsdaMacros = {
  kcal: 250,
  protein_g: 20,
  carbs_g: 30,
  fat_g: 10,
  description: "Chicken breast, grilled",
  servingGrams: 100,
  fdcId: 123456,
};

// ---------------------------------------------------------------------------
// scaleUsda
// ---------------------------------------------------------------------------
describe("scaleUsda", () => {
  it("doubles all values for a 200g portion", () => {
    const result = scaleUsda(baseMacros, 200);
    expect(result).toEqual({
      kcal: 500,
      protein_g: 40,
      carbs_g: 60,
      fat_g: 20,
    });
  });

  it("halves all values for a 50g portion", () => {
    const result = scaleUsda(baseMacros, 50);
    expect(result).toEqual({
      kcal: 125,
      protein_g: 10,
      carbs_g: 15,
      fat_g: 5,
    });
  });

  it("returns the same values for a 100g portion", () => {
    const result = scaleUsda(baseMacros, 100);
    expect(result).toEqual({
      kcal: 250,
      protein_g: 20,
      carbs_g: 30,
      fat_g: 10,
    });
  });

  it("returns all zeros for a 0g portion", () => {
    const result = scaleUsda(baseMacros, 0);
    expect(result).toEqual({
      kcal: 0,
      protein_g: 0,
      carbs_g: 0,
      fat_g: 0,
    });
  });
});
