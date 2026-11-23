/**
 * Validazione del piano del medico o dietista prima del salvataggio (funzione save-professional-plan).
 * Prima controlla la forma del JSON (il client non è fidato), poi applica le stesse regole dell'app
 * (`validateProfessionalPlan`, uguale a `ProfessionalPlan.validate()` in Swift).
 */
import { type ProfessionalPlan, validateProfessionalPlan } from "./nutrition.ts";

export type PlanPayloadIssue =
  | "invalid_shape" | "caloriesOutOfRange" | "macroOutOfRange" | "macrosDoNotMatchCalories" | "notesTooLong"
  | "nameTooLong" | "reviewBeforeStart" | "mealPlanInvalid";

const PROFESSIONALS = ["doctor", "dietitian", "nutritionist"];
const isObj = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);
const isDate = (v: unknown) => typeof v === "string" && !Number.isNaN(Date.parse(v));
const optDate = (v: unknown) => v === undefined || v === null || isDate(v);
const optInt = (v: unknown) => v === undefined || v === null || Number.isInteger(v);
const optText = (v: unknown) => v === undefined || v === null || typeof v === "string";

/** Forma del piano settimanale: giorni → pasti → alimenti. */
function hasMealPlanShape(v: unknown): boolean {
  if (v === undefined || v === null) return true;
  if (!Array.isArray(v)) return false;
  return v.every((day) => isObj(day) && optInt(day.week) && optInt(day.weekday) && Array.isArray(day.meals)
    && day.meals.every((meal) => isObj(meal) && typeof meal.type === "string" && Array.isArray(meal.foods)
      && meal.foods.every((f) => isObj(f) && typeof f.name === "string" && typeof f.grams === "number")));
}

/** Problemi trovati (vuoto = valido). */
export function validateProfessionalPlanPayload(plan: unknown): PlanPayloadIssue[] {
  if (!isObj(plan)) return ["invalid_shape"];
  const p = plan;
  const shapeOK = PROFESSIONALS.includes(p.professional as string)
    && typeof p.calorieTarget === "number"
    && optInt(p.proteinG) && optInt(p.carbsG) && optInt(p.fatG)
    && optText(p.notes) && optText(p.professionalName)
    && isDate(p.startDate) && isDate(p.confirmedAt) && optDate(p.reviewDate) && optDate(p.rotationAnchor)
    && optInt(p.rotationWeeks)
    && hasMealPlanShape(p.mealPlan);
  if (!shapeOK) return ["invalid_shape"];
  return validateProfessionalPlan(p as unknown as ProfessionalPlan);
}
