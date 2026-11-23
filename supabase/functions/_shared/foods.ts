/**
 * Conversione dei risultati di USDA FoodData Central e Open Food Facts nel formato FoodItem dell'app.
 * Valori sempre per 100 g. Gli alimenti con valori mancanti o non plausibili vengono scartati
 * (stessi limiti del vincolo `meal_items_valid` nel database).
 */

export interface Nutrients { kcal: number; proteinG: number; carbsG: number; fatG: number }
export interface FoodItem {
  id: string;
  name: string;
  brand?: string | null;
  per100g: Nutrients;
  source: "usda" | "open_food_facts" | "custom";
  defaultServingG?: number | null;
}

const round1 = (v: number) => Math.round(v * 10) / 10;
const isPlausible = (n: Nutrients) =>
  [n.kcal, n.proteinG, n.carbsG, n.fatG].every((v) => Number.isFinite(v) && v >= 0)
  && n.kcal <= 900 && n.proteinG <= 100 && n.carbsG <= 100 && n.fatG <= 100
  && n.proteinG + n.carbsG + n.fatG <= 105;

/** UUID stabile (formato v5) da una chiave, così lo stesso alimento ha sempre lo stesso id. */
export async function stableUUID(key: string): Promise<string> {
  const hash = new Uint8Array(await crypto.subtle.digest("SHA-1", new TextEncoder().encode(`caloscan:${key}`)));
  hash[6] = (hash[6] & 0x0f) | 0x50;
  hash[8] = (hash[8] & 0x3f) | 0x80;
  const hex = [...hash.slice(0, 16)].map((b) => b.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
}

// --- USDA FoodData Central (/foods/search) --------------------------------------------------

interface USDANutrient { nutrientId?: number; nutrientNumber?: string; unitName?: string; value?: number }
export interface USDAFood {
  fdcId: number;
  description: string;
  dataType?: string;
  brandOwner?: string;
  brandName?: string;
  foodNutrients?: USDANutrient[];
  servingSize?: number;
  servingSizeUnit?: string;
}

/** Tipi di dato preferiti: prima gli alimenti generici di laboratorio, poi i prodotti di marca. */
export const USDA_DATA_TYPES = ["Foundation", "SR Legacy", "Survey (FNDDS)", "Branded"];

function usdaValue(f: USDAFood, ids: number[], unit?: string): number | null {
  for (const id of ids) {
    const n = f.foodNutrients?.find((x) => x.nutrientId === id && (!unit || x.unitName?.toUpperCase() === unit));
    if (n && typeof n.value === "number") return n.value;
  }
  return null;
}

export async function fromUSDA(f: USDAFood, displayName?: string): Promise<FoodItem | null> {
  // Energia: 1008 (kcal); per i dati Foundation spesso solo 2047/2048 (fattori di Atwater).
  const kcal = usdaValue(f, [1008, 2048, 2047], "KCAL");
  const per100g = {
    kcal: kcal ?? NaN,
    proteinG: usdaValue(f, [1003]) ?? NaN,
    carbsG: usdaValue(f, [1005]) ?? 0,
    fatG: usdaValue(f, [1004]) ?? NaN,
  };
  if (!isPlausible(per100g) || typeof f.description !== "string") return null;
  const serving = f.servingSizeUnit?.toLowerCase() === "g" && typeof f.servingSize === "number"
    && f.servingSize >= 1 && f.servingSize <= 3000 ? Math.round(f.servingSize) : null;
  return {
    id: await stableUUID(`usda:${f.fdcId}`),
    name: (displayName ?? f.description).slice(0, 120),
    brand: f.dataType === "Branded" ? (f.brandName || f.brandOwner || null) : null,
    per100g: { kcal: Math.round(per100g.kcal), proteinG: round1(per100g.proteinG), carbsG: round1(per100g.carbsG), fatG: round1(per100g.fatG) },
    source: "usda",
    defaultServingG: serving,
  };
}

// --- Open Food Facts ---------------------------------------------------------------------------

export interface OFFProduct {
  code?: string;
  product_name?: string;
  product_name_it?: string;
  generic_name_it?: string;
  brands?: string;
  serving_quantity?: number | string;
  nutriments?: Record<string, number | string | undefined>;
}

const num = (v: unknown) => (typeof v === "number" ? v : typeof v === "string" && v.trim() !== "" ? Number(v) : NaN);

export async function fromOFF(p: OFFProduct): Promise<FoodItem | null> {
  const n = p.nutriments ?? {};
  const kj = num(n["energy_100g"]);
  let kcal = num(n["energy-kcal_100g"]);
  if (!Number.isFinite(kcal) && Number.isFinite(kj)) kcal = kj / 4.184;
  const per100g = {
    kcal,
    proteinG: num(n["proteins_100g"]),
    carbsG: num(n["carbohydrates_100g"]),
    fatG: num(n["fat_100g"]),
  };
  const name = (p.product_name_it || p.product_name || p.generic_name_it || "").trim();
  if (!name || !p.code || !isPlausible(per100g)) return null;
  const serving = num(p.serving_quantity);
  return {
    id: await stableUUID(`off:${p.code}`),
    name: name.slice(0, 120),
    brand: p.brands ? p.brands.split(",")[0].trim().slice(0, 60) || null : null,
    per100g: { kcal: Math.round(per100g.kcal), proteinG: round1(per100g.proteinG), carbsG: round1(per100g.carbsG), fatG: round1(per100g.fatG) },
    source: "open_food_facts",
    defaultServingG: Number.isFinite(serving) && serving >= 1 && serving <= 3000 ? Math.round(serving) : null,
  };
}

/** Codice a barre EAN/UPC: solo cifre, 8–14. */
export function isBarcode(v: unknown): v is string {
  return typeof v === "string" && /^\d{8,14}$/.test(v);
}

/** Chiave di cache della ricerca: minuscolo, spazi singoli. */
export function normalizeQuery(q: unknown): string | null {
  if (typeof q !== "string") return null;
  const s = q.normalize("NFC").toLowerCase().replace(/[\u0000-\u001f]/g, " ").replace(/\s+/g, " ").trim();
  return s.length >= 2 && s.length <= 80 && /\p{L}/u.test(s) ? s : null;
}
