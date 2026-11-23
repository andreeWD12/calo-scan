/**
 * Ricerca alimenti: { query } → { foods: FoodItem[] }, { barcode } → { food: FoodItem | null }.
 * Unisce USDA FoodData Central (alimenti generici, nomi tradotti in italiano dall'AI) e Open Food Facts
 * (prodotti venduti in Italia). I risultati sono messi in cache per 30 giorni (tabella food_search_cache):
 * contengono solo dati pubblici sugli alimenti, nessun dato dell'utente.
 */
import { errorResponse } from "../_shared/errors.ts";
import { type FoodItem, fromUSDA, isBarcode, normalizeQuery } from "../_shared/foods.ts";
import { lookupBarcode, searchOFF, searchUSDA } from "../_shared/fooddb.ts";
import { AIUnavailableError, isAIConfigured, toEnglishQuery, toItalianNames } from "../_shared/ai.ts";
import { adminClient, json, readJSON, requireUser } from "../_shared/supabase.ts";

const CACHE_DAYS = 30;
const MAX_RESULTS = 25;

Deno.serve(async (req) => {
  if (req.method !== "POST") return errorResponse("invalid_input");
  const admin = adminClient();
  const auth = await requireUser(req, admin);
  if (auth instanceof Response) return auth;

  const body = await readJSON(req, 2048) as { query?: unknown; barcode?: unknown } | null;
  if (!body) return errorResponse("invalid_input");

  if (body.barcode !== undefined) {
    if (!isBarcode(body.barcode)) return errorResponse("invalid_input", { message: "Codice a barre non valido." });
    const key = `barcode:${body.barcode}`;
    const cached = await readCache(admin, key);
    if (cached) return json({ food: cached[0] ?? null });
    const food = await lookupBarcode(body.barcode);
    await writeCache(admin, key, food ? [food] : []);
    return json({ food });
  }

  const query = normalizeQuery(body.query);
  if (!query) return errorResponse("invalid_input", { message: "Scrivi almeno due lettere." });
  const key = `query:${query}`;
  const cached = await readCache(admin, key);
  if (cached) return json({ foods: cached });

  const [usda, off] = await Promise.all([usdaInItalian(query), searchOFF(query, 10)]);
  const seen = new Set<string>();
  const foods = [...usda, ...off].filter((f) => {
    const k = `${f.name.toLowerCase()}|${f.brand ?? ""}`;
    if (seen.has(k)) return false;
    seen.add(k);
    return true;
  }).slice(0, MAX_RESULTS);
  if (foods.length > 0) await writeCache(admin, key, foods);
  return json({ foods });
});

/** USDA è in inglese: la ricerca viene tradotta e i nomi dei risultati riportati in italiano. */
async function usdaInItalian(query: string): Promise<FoodItem[]> {
  let english = query;
  let translate = isAIConfigured();
  if (translate) {
    try {
      english = (await toEnglishQuery(query)) ?? query;
    } catch (e) {
      if (!(e instanceof AIUnavailableError)) throw e;
      translate = false;
    }
  }
  const raw = (await searchUSDA(english, 12)).slice(0, 12);
  let names: (string | undefined)[] = raw.map(() => undefined);
  if (translate && raw.length > 0) {
    try {
      names = (await toItalianNames(raw.map((f) => f.description))) ?? names;
    } catch (e) {
      if (!(e instanceof AIUnavailableError)) throw e;
    }
  }
  const items = await Promise.all(raw.map((f, i) => fromUSDA(f, names[i])));
  return items.filter((i): i is FoodItem => i !== null);
}

type Admin = ReturnType<typeof adminClient>;

async function readCache(admin: Admin, key: string): Promise<FoodItem[] | null> {
  const since = new Date(Date.now() - CACHE_DAYS * 86_400_000).toISOString();
  const { data, error } = await admin.from("food_search_cache").select("results")
    .eq("query_key", key).gte("created_at", since).maybeSingle();
  if (error) {
    console.error("food-search: cache non leggibile", error.code);
    return null;
  }
  return Array.isArray(data?.results) ? data.results as FoodItem[] : null;
}

async function writeCache(admin: Admin, key: string, results: FoodItem[]) {
  const { error } = await admin.from("food_search_cache")
    .upsert({ query_key: key, results, created_at: new Date().toISOString() }, { onConflict: "query_key" });
  if (error) console.error("food-search: cache non scritta", error.code);
}
