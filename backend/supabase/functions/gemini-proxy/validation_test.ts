// =============================================================================
// THERMO AI — Deno unit tests for response validation
// File: backend/supabase/functions/gemini-proxy/validation_test.ts
// Run (by the implementation agent): deno test backend/supabase/functions/gemini-proxy
// =============================================================================

import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { validateChatReply, validateFoodAnalysis, validateMealPlan, ValidationError } from "./validation.ts";

Deno.test("food analysis keeps consistent items", () => {
  const out = validateFoodAnalysis({
    isFood: true,
    items: [{ name: "Rice", portionDescription: "1 cup", estimatedGrams: 158, calories: 205, proteinG: 4.3, carbsG: 44.5, fatG: 0.4, fiberG: 0.6, confidence: 0.9 }],
    notes: "",
  });
  assertEquals(out.items[0].calories, 205);
  assertEquals(out.items[0].confidence, 0.9);
});

Deno.test("food analysis corrects inconsistent calories and lowers confidence", () => {
  const out = validateFoodAnalysis({
    isFood: true,
    items: [{ name: "Steak", portionDescription: "200 g", estimatedGrams: 200, calories: 100, proteinG: 50, carbsG: 0, fatG: 20, fiberG: 0, confidence: 0.95 }],
    notes: "",
  });
  assertEquals(out.items[0].calories, 380); // 4*50 + 9*20
  assertEquals(out.items[0].confidence, 0.5);
});

Deno.test("food analysis clamps negatives", () => {
  const out = validateFoodAnalysis({
    isFood: true,
    items: [{ name: "X", portionDescription: "", estimatedGrams: -5, calories: 0, proteinG: -1, carbsG: 0, fatG: 0, fiberG: 0, confidence: 2 }],
    notes: "",
  });
  assertEquals(out.items[0].estimatedGrams, 0);
  assertEquals(out.items[0].proteinG, 0);
  assertEquals(out.items[0].confidence, 1);
});

Deno.test("non-food result is isFood=false", () => {
  const out = validateFoodAnalysis({ isFood: false, items: [], notes: "A cat" });
  assertEquals(out.isFood, false);
});

Deno.test("chat reply requires text", () => {
  assertThrows(() => validateChatReply({ reply: "", suggestions: [] }), ValidationError);
  assertEquals(validateChatReply({ reply: "Hi", suggestions: ["a", "b", "c", "d"] }).suggestions.length, 3);
});

Deno.test("meal plan computes totals and deviation", () => {
  const out = validateMealPlan(
    { title: "Plan", notes: "", days: [{ dayIndex: 1, meals: [
      { mealType: "breakfast", name: "Oats", description: "", ingredients: [], calories: 1000, proteinG: 40, carbsG: 120, fatG: 30 },
      { mealType: "brunch", name: "Eggs", description: "", ingredients: [], calories: 1000, proteinG: 60, carbsG: 20, fatG: 60 },
    ] }] },
    { calories: 2000, proteinG: 100, carbsG: 140, fatG: 90 },
    1,
  );
  assertEquals(out.days[0].totalCalories, 2000);
  assertEquals(out.days[0].calorieDeviation, 0);
  assertEquals(out.days[0].meals[1].mealType, "snack"); // invalid enum coerced
});
