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
  source: "usda" | "open_food_facts" | "custom" | "ai_estimate";
  defaultServingG?: number | null;
}

const round1 = (v: number) => Math.round(v * 10) / 10;
export const isPlausible = (n: Nutrients) =>
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
    brand: null,
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
  lang?: string;
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
  const name = cleanProductName(p.product_name_it || p.product_name || p.generic_name_it || "", p.brands);
  if (!name || !p.code || !isPlausible(per100g)) return null;
  const serving = num(p.serving_quantity);
  return {
    id: await stableUUID(`off:${p.code}`),
    name: name.slice(0, 120),
    // Marchi e insegne non vengono mostrati: nell'app conta l'alimento, non il negozio.
    brand: null,
    per100g: { kcal: Math.round(per100g.kcal), proteinG: round1(per100g.proteinG), carbsG: round1(per100g.carbsG), fatG: round1(per100g.fatG) },
    source: "open_food_facts",
    defaultServingG: Number.isFinite(serving) && serving >= 1 && serving <= 3000 ? Math.round(serving) : null,
  };
}

/** Insegne della grande distribuzione che compaiono spesso nei nomi dei prodotti a marchio. */
const RETAILERS = [
  "esselunga", "coop", "conad", "carrefour", "lidl", "eurospin", "despar", "eurospar", "interspar", "spar",
  "pam", "panorama", "md", "penny", "aldi", "iper", "ipercoop", "bennet", "famila", "crai", "sigma", "tigre",
  "selex", "il viaggiator goloso", "viaggiator goloso", "auchan", "unes", "tuodì", "todis",
  "deco", "gs", "dimeglio", "naturasì", "naturasi", "fior fiore", "vivi verde", "terre d'italia",
];

const escapeRegExp = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/** Nome del prodotto senza marchio né insegna (es. "Spaghetti n.5 Barilla" → "Spaghetti n.5"). */
export function cleanProductName(raw: string, brands?: string): string {
  const words = [
    ...(brands ?? "").split(",").map((b) => b.trim().toLowerCase()).filter((b) => b.length >= 2),
    ...RETAILERS,
  ].sort((a, b) => b.length - a.length);
  let name = raw.normalize("NFC");
  for (const w of words) {
    name = name.replace(new RegExp(`(^|[\\s,()\\-–])${escapeRegExp(w)}(?=$|[\\s,()\\-–])`, "giu"), "$1");
  }
  name = name.replace(/\(\s*\)/g, "").replace(/\s+/g, " ").replace(/^[\s,\-–]+|[\s,\-–]+$/g, "").trim();
  if (!name) return "";
  return (name[0].toLocaleUpperCase("it") + name.slice(1)).slice(0, 120);
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

/**
 * Alimento con valori per 100 g stimati dall'AI, usato solo se nessun database ha un riscontro.
 * Le calorie devono essere coerenti con le macro (4/4/9 kcal per grammo, ±25%), altrimenti si ricalcolano.
 */
export async function aiEstimateFood(name: string, raw: Nutrients): Promise<FoodItem | null> {
  const fromMacros = 4 * raw.proteinG + 4 * raw.carbsG + 9 * raw.fatG;
  const kcal = Number.isFinite(raw.kcal) && fromMacros > 0 && Math.abs(raw.kcal - fromMacros) / fromMacros <= 0.25
    ? raw.kcal
    : fromMacros;
  const per100g = { kcal, proteinG: raw.proteinG, carbsG: raw.carbsG, fatG: raw.fatG };
  if (!name || !isPlausible(per100g) || (kcal === 0 && name.length === 0)) return null;
  const rounded = { kcal: Math.round(kcal), proteinG: round1(raw.proteinG), carbsG: round1(raw.carbsG), fatG: round1(raw.fatG) };
  return {
    id: await stableUUID(`ai:${name.toLowerCase()}:${rounded.kcal}:${rounded.proteinG}:${rounded.carbsG}:${rounded.fatG}`),
    name: name.slice(0, 120),
    brand: null,
    per100g: rounded,
    source: "ai_estimate",
    defaultServingG: null,
  };
}

/** Nome leggibile per un utente italiano: niente alfabeti non latini (es. ebraico, cirillico). */
export function isLatinName(name: string): boolean {
  return !/[^\p{Script=Latin}\p{N}\p{P}\p{Zs}\p{S}]/u.test(name);
}

/**
 * Sceglie tra il riscontro del database e la stima dell'AI. Vince il database, a meno che le calorie
 * siano così diverse (meno di 0,55 o più di 1,8 volte) da far pensare a un abbinamento sbagliato,
 * per esempio un sugo pronto americano molto zuccherato al posto di un sugo di pomodoro.
 */
export function pickFood(db: FoodItem | null, estimate: FoodItem | null): FoodItem | null {
  if (!db || !estimate) return db ?? estimate;
  const a = db.per100g.kcal, b = estimate.per100g.kcal;
  if (a < 20 && b < 20) return db;
  const ratio = a / Math.max(b, 1);
  return ratio < 0.55 || ratio > 1.8 ? estimate : db;
}
