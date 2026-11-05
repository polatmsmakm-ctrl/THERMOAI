// =============================================================================
// THERMO AI — JSON Schemas passed to Gemini as generationConfig.responseJsonSchema
// File: backend/supabase/functions/gemini-proxy/schemas.ts
// These shapes mirror the Swift DTOs in THERMOAI/Models/AIModels.swift exactly.
// =============================================================================

const macroProps = {
  calories: { type: "number", minimum: 0, description: "Kilocalories" },
  proteinG: { type: "number", minimum: 0, description: "Protein in grams" },
  carbsG: { type: "number", minimum: 0, description: "Total carbohydrates in grams" },
  fatG: { type: "number", minimum: 0, description: "Total fat in grams" },
};

export const FOOD_ANALYSIS_SCHEMA = {
  type: "object",
  properties: {
    isFood: { type: "boolean", description: "False if no food or drink is present." },
    items: {
      type: "array",
      description: "Each distinct food item detected.",
      items: {
        type: "object",
        properties: {
          name: { type: "string", description: "Common English food name." },
          portionDescription: { type: "string", description: "Human-readable portion, e.g. '1 cup', '2 slices'." },
          estimatedGrams: { type: "number", minimum: 0, description: "Estimated edible weight in grams." },
          ...macroProps,
          fiberG: { type: "number", minimum: 0 },
          confidence: { type: "number", minimum: 0, maximum: 1, description: "0-1 confidence in identification and portion." },
        },
        required: ["name", "portionDescription", "estimatedGrams", "calories", "proteinG", "carbsG", "fatG", "fiberG", "confidence"],
      },
    },
    notes: { type: "string", description: "Short caveats, e.g. hidden oils or sauces." },
  },
  required: ["isFood", "items", "notes"],
};

export const CHAT_SCHEMA = {
  type: "object",
  properties: {
    reply: { type: "string", description: "Markdown-free conversational answer." },
    suggestions: {
      type: "array",
      items: { type: "string" },
      description: "Up to 3 short follow-up questions the user might ask.",
    },
  },
  required: ["reply", "suggestions"],
};

export const MEAL_PLAN_SCHEMA = {
  type: "object",
  properties: {
    title: { type: "string" },
    days: {
      type: "array",
      items: {
        type: "object",
        properties: {
          dayIndex: { type: "integer", minimum: 1 },
          meals: {
            type: "array",
            items: {
              type: "object",
              properties: {
                mealType: { type: "string", enum: ["breakfast", "lunch", "dinner", "snack"] },
                name: { type: "string" },
                description: { type: "string" },
                ingredients: { type: "array", items: { type: "string" } },
                ...macroProps,
              },
              required: ["mealType", "name", "description", "ingredients", "calories", "proteinG", "carbsG", "fatG"],
            },
          },
        },
        required: ["dayIndex", "meals"],
      },
    },
    notes: { type: "string" },
  },
  required: ["title", "days", "notes"],
};
