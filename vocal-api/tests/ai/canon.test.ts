import { describe, it, expect } from "vitest";
import { matchChain, parseChipotleBowl, CHAIN_CANON } from "../../src/ai/canon";

// ---------------------------------------------------------------------------
// matchChain
// ---------------------------------------------------------------------------
describe("matchChain", () => {
  it("returns null for non-chain transcripts", () => {
    expect(matchChain("scrambled eggs")).toBeNull();
    expect(matchChain("homemade pasta")).toBeNull();
    expect(matchChain("a sandwich I made")).toBeNull();
  });

  it("returns null when the chain is recognized but no item matches", () => {
    // "mcdonald's" matches the brand, but "salad deluxe" isn't in the canon
    expect(matchChain("mcdonald's salad deluxe")).toBeNull();
  });

  // -- McDonald's ---------------------------------------------------------

  describe("McDonald's items", () => {
    it("matches Big Mac with correct macros", () => {
      const result = matchChain("mcdonald's big mac");
      expect(result).not.toBeNull();
      expect(result!.name).toBe("McDonald's Big Mac");
      expect(result!.kcal).toBe(590);
      expect(result!.protein_g).toBe(25);
      expect(result!.carbs_g).toBe(45);
      expect(result!.fat_g).toBe(34);
      expect(result!.sodium_mg).toBe(1050);
    });

    it("matches Quarter Pounder", () => {
      const result = matchChain("mcdonald's quarter pounder");
      expect(result).not.toBeNull();
      expect(result!.name).toBe("McDonald's Quarter Pounder with Cheese");
      expect(result!.kcal).toBe(520);
      expect(result!.protein_g).toBe(30);
    });

    it("matches McChicken", () => {
      const result = matchChain("mcdonald's mcchicken");
      expect(result).not.toBeNull();
      expect(result!.name).toBe("McDonald's McChicken");
      expect(result!.kcal).toBe(400);
      expect(result!.protein_g).toBe(14);
    });

    it("matches McNuggets", () => {
      const result = matchChain("mcdonald's mcnugget");
      expect(result).not.toBeNull();
      expect(result!.name).toBe("McDonald's Chicken McNuggets (10 pc)");
      expect(result!.kcal).toBe(410);
    });

    it("matches Egg McMuffin", () => {
      const result = matchChain("mcdonalds egg mcmuffin");
      expect(result).not.toBeNull();
      expect(result!.name).toBe("McDonald's Egg McMuffin");
      expect(result!.kcal).toBe(310);
      expect(result!.protein_g).toBe(17);
      expect(result!.slot).toBe("breakfast");
    });

    it("matches fries defaulting to Medium when no size given", () => {
      const result = matchChain("mcdonald's fries");
      expect(result).not.toBeNull();
      expect(result!.name).toBe("McDonald's French Fries (Medium)");
      expect(result!.kcal).toBe(320);
      expect(result!.protein_g).toBe(4);
      expect(result!.carbs_g).toBe(43);
      expect(result!.fat_g).toBe(15);
    });

    it("more specific match wins: large fries beat medium", () => {
      const result = matchChain("mcdonald's fries large");
      expect(result).not.toBeNull();
      expect(result!.name).toBe("McDonald's French Fries (Large)");
      expect(result!.kcal).toBe(480);
      expect(result!.protein_g).toBe(7);
      expect(result!.carbs_g).toBe(66);
      expect(result!.fat_g).toBe(23);
      expect(result!.sodium_mg).toBe(400);
    });

    it("matches small fries", () => {
      const result = matchChain("mcdonald's fries small");
      expect(result).not.toBeNull();
      expect(result!.name).toBe("McDonald's French Fries (Small)");
      expect(result!.kcal).toBe(230);
    });

    it("matches via brand alias 'mcd'", () => {
      const result = matchChain("mcd fries");
      expect(result).not.toBeNull();
      expect(result!.name).toBe("McDonald's French Fries (Medium)");
      expect(result!.kcal).toBe(320);
    });
  });

  // -- Starbucks -----------------------------------------------------------

  describe("Starbucks items", () => {
    it("matches Caffe Latte", () => {
      const result = matchChain("starbucks latte");
      expect(result).not.toBeNull();
      expect(result!.name).toBe("Starbucks Caffe Latte (Grande)");
      expect(result!.kcal).toBe(190);
      expect(result!.protein_g).toBe(13);
      expect(result!.carbs_g).toBe(18);
      expect(result!.fat_g).toBe(7);
    });

    it("matches Cold Brew", () => {
      const result = matchChain("starbucks cold brew");
      expect(result).not.toBeNull();
      expect(result!.name).toBe("Starbucks Cold Brew (Grande)");
      expect(result!.kcal).toBe(5);
    });

    it("matches Frappuccino", () => {
      const result = matchChain("starbucks frappuccino");
      expect(result).not.toBeNull();
      expect(result!.name).toBe("Starbucks Caramel Frappuccino (Grande)");
      expect(result!.kcal).toBe(380);
      expect(result!.slot).toBe("snack");
    });

    it("matches Pumpkin Spice Latte via 'psl' alias", () => {
      const result = matchChain("starbucks psl");
      expect(result).not.toBeNull();
      expect(result!.name).toBe("Starbucks Pumpkin Spice Latte (Grande)");
      expect(result!.kcal).toBe(390);
      expect(result!.protein_g).toBe(14);
      expect(result!.carbs_g).toBe(52);
      expect(result!.fat_g).toBe(14);
    });

    it("'pumpkin spice latte' hits generic latte first (linear scan)", () => {
      // The generic ["latte"] pattern is listed before ["pumpkin","spice","latte"]
      // so the first-match-wins scan returns the Caffe Latte.
      const result = matchChain("starbucks pumpkin spice latte");
      expect(result).not.toBeNull();
      expect(result!.name).toBe("Starbucks Caffe Latte (Grande)");
    });

    it("matches Iced Oatmilk Latte", () => {
      const result = matchChain("starbucks iced oat latte");
      expect(result).not.toBeNull();
      expect(result!.name).toBe("Starbucks Iced Oatmilk Latte (Grande)");
      expect(result!.kcal).toBe(190);
    });

    it("matches via brand alias 'sbux'", () => {
      const result = matchChain("sbux cold brew");
      expect(result).not.toBeNull();
      expect(result!.name).toBe("Starbucks Cold Brew (Grande)");
    });
  });

  // -- Other chains --------------------------------------------------------

  describe("Chick-fil-A items", () => {
    it("matches Chicken Sandwich", () => {
      const result = matchChain("chick-fil-a chicken sandwich");
      expect(result).not.toBeNull();
      expect(result!.name).toBe("Chick-fil-A Chicken Sandwich");
      expect(result!.kcal).toBe(420);
      expect(result!.protein_g).toBe(28);
      expect(result!.sodium_mg).toBe(1400);
    });

    it("matches Waffle Fries", () => {
      const result = matchChain("chickfila waffle fries");
      expect(result).not.toBeNull();
      expect(result!.name).toBe("Chick-fil-A Waffle Fries (Medium)");
      expect(result!.kcal).toBe(420);
      expect(result!.slot).toBe("snack");
    });
  });

  describe("Burger King items", () => {
    it("matches Whopper", () => {
      const result = matchChain("burger king whopper");
      expect(result).not.toBeNull();
      expect(result!.name).toBe("Burger King Whopper");
      expect(result!.kcal).toBe(670);
      expect(result!.protein_g).toBe(28);
      expect(result!.fat_g).toBe(40);
    });
  });

  describe("Subway items", () => {
    it("matches Turkey Footlong", () => {
      const result = matchChain("subway turkey footlong");
      expect(result).not.toBeNull();
      expect(result!.name).toBe("Subway Turkey Footlong");
      expect(result!.kcal).toBe(560);
      expect(result!.protein_g).toBe(36);
    });

    it("matches Italian BMT", () => {
      const result = matchChain("subway italian bmt");
      expect(result).not.toBeNull();
      expect(result!.name).toBe("Subway Italian B.M.T. (6 inch)");
      expect(result!.kcal).toBe(420);
    });
  });

  describe("Taco Bell items", () => {
    it("matches Crunchwrap Supreme", () => {
      const result = matchChain("taco bell crunchwrap supreme");
      expect(result).not.toBeNull();
      expect(result!.name).toBe("Taco Bell Crunchwrap Supreme");
      expect(result!.kcal).toBe(530);
    });

    it("matches Crunchy Taco", () => {
      const result = matchChain("taco bell crunchy taco");
      expect(result).not.toBeNull();
      expect(result!.name).toBe("Taco Bell Crunchy Taco");
      expect(result!.kcal).toBe(170);
      expect(result!.slot).toBe("snack");
    });
  });

  // -- Shared return-shape assertions --------------------------------------

  it("always returns source:'voice' and confidence:0.95", () => {
    const result = matchChain("mcdonalds big mac");
    expect(result).not.toBeNull();
    expect(result!.source).toBe("voice");
    expect(result!.confidence).toBe(0.95);
  });

  it("populates the slot from the canon item", () => {
    const lunch = matchChain("burger king whopper");
    expect(lunch!.slot).toBe("lunch");

    const snack = matchChain("mcdonald's fries");
    expect(snack!.slot).toBe("snack");

    const breakfast = matchChain("starbucks latte");
    expect(breakfast!.slot).toBe("breakfast");
  });

  it("is case-insensitive", () => {
    expect(matchChain("McDonald's BIG MAC")).not.toBeNull();
    expect(matchChain("STARBUCKS COLD BREW")).not.toBeNull();
  });
});

// ---------------------------------------------------------------------------
// parseChipotleBowl
// ---------------------------------------------------------------------------
describe("parseChipotleBowl", () => {
  it("returns null when transcript has no chipotle mention", () => {
    expect(parseChipotleBowl("scrambled eggs", null)).toBeNull();
  });

  it("returns null when transcript says chipotle but not bowl", () => {
    expect(parseChipotleBowl("chipotle burrito", null)).toBeNull();
  });

  it("returns null when transcript says bowl but not chipotle", () => {
    expect(parseChipotleBowl("poke bowl", null)).toBeNull();
  });

  // -- Default bowl (no guac, single chicken) ------------------------------

  it("returns a meal for a plain 'chipotle bowl'", () => {
    const result = parseChipotleBowl("chipotle bowl", null);
    expect(result).not.toBeNull();
    expect("meal" in result!).toBe(true);

    const { meal } = result as { meal: any };
    expect(meal.name).toBe("Chipotle Chicken Bowl");
    // rice 210 + beans 130 + single chicken 180 = 520
    expect(meal.kcal).toBe(520);
    expect(meal.protein_g).toBe(32 + 9); // chicken + beans
    expect(meal.carbs_g).toBe(45 + 22);  // rice + beans
    expect(meal.fat_g).toBe(7 + 2);      // chicken + beans
    expect(meal.slot).toBe("lunch");
    expect(meal.source).toBe("voice");
    expect(meal.confidence).toBe(0.93);
    expect(meal.detail).toContain("single chicken");
  });

  // -- Guac follow-up flow -------------------------------------------------

  it("asks a follow-up when guac is mentioned but no answer given", () => {
    const result = parseChipotleBowl("chipotle bowl with guac", null);
    expect(result).not.toBeNull();
    expect("followUp" in result!).toBe(true);

    const fu = result as { followUp: string; reasoning: string };
    expect(fu.followUp).toBe("Single scoop of guac?");
    expect(fu.reasoning).toBeTruthy();
  });

  it("asks a follow-up when guac mentioned and followUpAnswer is undefined", () => {
    const result = parseChipotleBowl("chipotle bowl with guac", undefined);
    expect(result).not.toBeNull();
    expect("followUp" in result!).toBe(true);
  });

  it("asks a follow-up when guac mentioned and followUpAnswer is empty string", () => {
    const result = parseChipotleBowl("chipotle bowl with guac", "");
    expect(result).not.toBeNull();
    expect("followUp" in result!).toBe(true);
  });

  it("returns meal with single guac when answer is 'single'", () => {
    const result = parseChipotleBowl("chipotle bowl with guac", "single");
    expect(result).not.toBeNull();
    expect("meal" in result!).toBe(true);

    const { meal } = result as { meal: any };
    // rice 210 + beans 130 + single chicken 180 + single guac 230 = 750
    expect(meal.kcal).toBe(750);
    expect(meal.protein_g).toBe(32 + 9);
    expect(meal.carbs_g).toBe(45 + 22 + 8);  // +8 for single guac
    expect(meal.fat_g).toBe(7 + 2 + 22);      // +22 for single guac
    expect(meal.detail).toContain("1× guac");
  });

  it("returns meal with double guac when answer is 'double'", () => {
    const result = parseChipotleBowl("chipotle bowl with guac", "double");
    expect(result).not.toBeNull();
    expect("meal" in result!).toBe(true);

    const { meal } = result as { meal: any };
    // rice 210 + beans 130 + single chicken 180 + double guac 460 = 980
    expect(meal.kcal).toBe(980);
    expect(meal.protein_g).toBe(32 + 9);
    expect(meal.carbs_g).toBe(45 + 22 + 16); // +16 for double guac
    expect(meal.fat_g).toBe(7 + 2 + 44);      // +44 for double guac
    expect(meal.detail).toContain("2× guac");
  });

  it("treats 'two' as double guac", () => {
    const result = parseChipotleBowl("chipotle bowl with guac", "two");
    expect(result).not.toBeNull();
    expect("meal" in result!).toBe(true);

    const { meal } = result as { meal: any };
    expect(meal.kcal).toBe(980);
    expect(meal.detail).toContain("2× guac");
  });

  // -- Double chicken -------------------------------------------------------

  it("handles double chicken with correct macros", () => {
    const result = parseChipotleBowl("chipotle bowl double chicken", null);
    expect(result).not.toBeNull();
    expect("meal" in result!).toBe(true);

    const { meal } = result as { meal: any };
    // rice 210 + beans 130 + double chicken 360 = 700
    expect(meal.kcal).toBe(700);
    expect(meal.protein_g).toBe(64 + 9);  // double chicken + beans
    expect(meal.carbs_g).toBe(45 + 22);
    expect(meal.fat_g).toBe(14 + 2);       // double chicken fat + beans
    expect(meal.detail).toContain("double chicken");
  });

  it("handles double chicken + single guac", () => {
    const result = parseChipotleBowl("chipotle bowl double chicken with guac", "single");
    expect(result).not.toBeNull();
    expect("meal" in result!).toBe(true);

    const { meal } = result as { meal: any };
    // rice 210 + beans 130 + double chicken 360 + single guac 230 = 930
    expect(meal.kcal).toBe(930);
    expect(meal.protein_g).toBe(64 + 9);
    expect(meal.fat_g).toBe(14 + 2 + 22);
  });

  it("handles double chicken + double guac", () => {
    const result = parseChipotleBowl("chipotle bowl double chicken with guac", "double");
    expect(result).not.toBeNull();
    expect("meal" in result!).toBe(true);

    const { meal } = result as { meal: any };
    // rice 210 + beans 130 + double chicken 360 + double guac 460 = 1160
    expect(meal.kcal).toBe(1160);
    expect(meal.fat_g).toBe(14 + 2 + 44);
  });

  // -- Return shape --------------------------------------------------------

  it("always sets source:'voice' and confidence:0.93 on meals", () => {
    const result = parseChipotleBowl("chipotle bowl", null) as { meal: any };
    expect(result.meal.source).toBe("voice");
    expect(result.meal.confidence).toBe(0.93);
  });
});

// ---------------------------------------------------------------------------
// CHAIN_CANON structure
// ---------------------------------------------------------------------------
describe("CHAIN_CANON", () => {
  it("is an array with at least 5 chains", () => {
    expect(Array.isArray(CHAIN_CANON)).toBe(true);
    expect(CHAIN_CANON.length).toBeGreaterThanOrEqual(5);
  });

  it("every chain has a brand, matchBrand[], and items[]", () => {
    for (const chain of CHAIN_CANON) {
      expect(typeof chain.brand).toBe("string");
      expect(Array.isArray(chain.matchBrand)).toBe(true);
      expect(chain.matchBrand.length).toBeGreaterThanOrEqual(1);
      expect(Array.isArray(chain.items)).toBe(true);
    }
  });

  it("every item has match[][], meal, and defaultSlot", () => {
    for (const chain of CHAIN_CANON) {
      for (const item of chain.items) {
        expect(Array.isArray(item.match)).toBe(true);
        expect(item.match.length).toBeGreaterThanOrEqual(1);
        for (const group of item.match) {
          expect(Array.isArray(group)).toBe(true);
          expect(group.length).toBeGreaterThanOrEqual(1);
        }
        expect(typeof item.meal.name).toBe("string");
        expect(typeof item.meal.kcal).toBe("number");
        expect(typeof item.meal.protein_g).toBe("number");
        expect(typeof item.meal.carbs_g).toBe("number");
        expect(typeof item.meal.fat_g).toBe("number");
        expect(["breakfast", "lunch", "dinner", "snack"]).toContain(item.defaultSlot);
      }
    }
  });

  it("includes Chipotle with empty items (bowls handled by parseChipotleBowl)", () => {
    const chipotle = CHAIN_CANON.find(c => c.brand === "Chipotle");
    expect(chipotle).toBeDefined();
    expect(chipotle!.items).toHaveLength(0);
  });
});
