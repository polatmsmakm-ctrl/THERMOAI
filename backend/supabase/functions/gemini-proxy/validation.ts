// =============================================================================
// THERMO AI — Server-side validation and sanitisation of Gemini output
// File: backend/supabase/functions/gemini-proxy/validation.ts
// Even with a response schema, model output is untrusted: clamp numbers,
// recompute totals, and reject structurally invalid data.
// =============================================================================

export class ValidationError extends Error {}

const MEAL_TYPES = ["breakfast", "lunch", "dinner", "snack"] as const;

function num(value: unknown, field: string, max: number): number {
  const n = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(n)) throw new ValidationError(`${field} is not a number`);
  return Math.round(Math.min(Math.max(n, 0), max) * 10) / 10;
}

function str(value: unknown, field: string, maxLen = 300): string {
  if (typeof value !== "string") throw new ValidationError(`${field} is not a string`);
  return value.trim().slice(0, maxLen);
}

/** Atwater energy from macros (kcal). */
function atwater(p: number, c: number, f: number): number {
  return 4 * p + 4 * c + 9 * f;
}

// deno-lint-ignore no-explicit-any
export function validateFoodAnalysis(raw: any) {
  if (typeof raw !== "object" || raw === null) throw new ValidationError("Response is not an object");
  const isFood = raw.isFood === true;
  const rawItems: unknown[] = Array.isArray(raw.items) ? raw.items.slice(0, 20) : [];

  // deno-lint-ignore no-explicit-any
  const items = rawItems.map((it: any, i: number) => {
    const proteinG = num(it.proteinG, `items[${i}].proteinG`, 500);
    const carbsG = num(it.carbsG, `items[${i}].carbsG`, 1000);
    const fatG = num(it.fatG, `items[${i}].fatG`, 500);
    let calories = num(it.calories, `items[${i}].calories`, 5000);
    let confidence = Math.min(Math.max(Number(it.confidence) || 0, 0), 1);

    // If stated calories disagree with macro energy by > 25%, trust the macros and lower confidence.
    const derived = atwater(proteinG, carbsG, fatG);
    if (derived > 0 && Math.abs(calories - derived) / derived > 0.25) {
      calories = Math.round(derived);
      confidence = Math.min(confidence, 0.5);
    }

    return {
      name: str(it.name, `items[${i}].name`, 120) || "Unknown food",
      portionDescription: str(it.portionDescription ?? "", `items[${i}].portionDescription`, 120),
      estimatedGrams: num(it.estimatedGrams, `items[${i}].estimatedGrams`, 3000),
      calories,
      proteinG,
      carbsG,
      fatG,
      fiberG: num(it.fiberG ?? 0, `items[${i}].fiberG`, 200),
      confidence: Math.round(confidence * 100) / 100,
    };
  });

  return {
    isFood: isFood && items.length > 0,
    items,
    notes: typeof raw.notes === "string" ? raw.notes.slice(0, 500) : "",
  };
}

// deno-lint-ignore no-explicit-any
export function validateChatReply(raw: any) {
  if (typeof raw !== "object" || raw === null) throw new ValidationError("Response is not an object");
  const reply = str(raw.reply, "reply", 4000);
  if (reply.length === 0) throw new ValidationError("Empty reply");
  const suggestions = Array.isArray(raw.suggestions)
    ? raw.suggestions.filter((s: unknown) => typeof s === "string").slice(0, 3).map((s: string) => s.slice(0, 120))
    : [];
  return { reply, suggestions };
}

export function validateMealPlan(
  // deno-lint-ignore no-explicit-any
  raw: any,
  targets: { calories: number; proteinG: number; carbsG: number; fatG: number },
  expectedDays: number,
) {
  if (typeof raw !== "object" || raw === null) throw new ValidationError("Response is not an object");
  if (!Array.isArray(raw.days) || raw.days.length === 0) throw new ValidationError("Plan has no days");

  // deno-lint-ignore no-explicit-any
  const days = raw.days.slice(0, expectedDays).map((d: any, di: number) => {
    if (!Array.isArray(d.meals) || d.meals.length === 0) throw new ValidationError(`Day ${di + 1} has no meals`);
    // deno-lint-ignore no-explicit-any
    const meals = d.meals.slice(0, 6).map((m: any, mi: number) => {
      const mealType = MEAL_TYPES.includes(m.mealType) ? m.mealType : "snack";
      return {
        mealType,
        name: str(m.name, `meal ${mi}.name`, 120),
        description: str(m.description ?? "", `meal ${mi}.description`, 400),
        ingredients: Array.isArray(m.ingredients)
          ? m.ingredients.filter((s: unknown) => typeof s === "string").slice(0, 20).map((s: string) => s.slice(0, 120))
          : [],
        calories: num(m.calories, `meal ${mi}.calories`, 3000),
        proteinG: num(m.proteinG, `meal ${mi}.proteinG`, 300),
        carbsG: num(m.carbsG, `meal ${mi}.carbsG`, 500),
        fatG: num(m.fatG, `meal ${mi}.fatG`, 300),
      };
    });
    const totalCalories = meals.reduce((s: number, m: { calories: number }) => s + m.calories, 0);
    const deviation = targets.calories > 0 ? (totalCalories - targets.calories) / targets.calories : 0;
    return { dayIndex: di + 1, meals, totalCalories: Math.round(totalCalories), calorieDeviation: Math.round(deviation * 1000) / 1000 };
  });

  return {
    title: typeof raw.title === "string" && raw.title.trim() ? raw.title.trim().slice(0, 120) : "Your meal plan",
    days,
    notes: typeof raw.notes === "string" ? raw.notes.slice(0, 600) : "",
  };
}
