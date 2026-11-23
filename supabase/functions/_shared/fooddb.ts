/**
 * Accesso ai database nutrizionali: USDA FoodData Central (pubblico dominio, chiave USDA_FDC_API_KEY)
 * e Open Food Facts (licenza ODbL, citato nell'app come fonte). Nessun dato dell'utente viene inviato:
 * solo il nome dell'alimento cercato o il codice a barre.
 */
import { type FoodItem, fromOFF, fromUSDA, type OFFProduct, type USDAFood, USDA_DATA_TYPES } from "./foods.ts";

const USER_AGENT = "CaloScan/1.0 (+https://andreewd12.github.io/calo-scan/support/)";
const OFF_FIELDS = "code,product_name,product_name_it,generic_name_it,brands,nutriments,serving_quantity";

/** Alimenti USDA grezzi per una ricerca in inglese. Senza chiave usa DEMO_KEY (limiti bassi, solo prove). */
export async function searchUSDA(query: string, pageSize = 10, dataTypes = USDA_DATA_TYPES): Promise<USDAFood[]> {
  const key = Deno.env.get("USDA_FDC_API_KEY") || "DEMO_KEY";
  try {
    const res = await fetch(`https://api.nal.usda.gov/fdc/v1/foods/search?api_key=${encodeURIComponent(key)}`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "User-Agent": USER_AGENT },
      body: JSON.stringify({ query, dataType: dataTypes, pageSize, requireAllWords: false }),
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) {
      console.error("usda: risposta", res.status);
      return [];
    }
    const json = await res.json() as { foods?: USDAFood[] };
    return Array.isArray(json.foods) ? json.foods : [];
  } catch (error) {
    console.error("usda: non raggiungibile", (error as Error).name);
    return [];
  }
}

/** Primo alimento USDA valido per un termine, con il nome italiano scelto da noi. */
export async function bestUSDAMatch(englishQuery: string, italianName: string): Promise<FoodItem | null> {
  const foods = await searchUSDA(englishQuery, 5, ["Foundation", "SR Legacy", "Survey (FNDDS)"]);
  for (const f of foods) {
    const item = await fromUSDA(f, italianName);
    if (item) return item;
  }
  return null;
}

/** Prodotti di Open Food Facts venduti in Italia, cercati per nome. */
export async function searchOFF(query: string, pageSize = 10): Promise<FoodItem[]> {
  const url = new URL("https://world.openfoodfacts.org/cgi/search.pl");
  url.search = new URLSearchParams({
    search_terms: query, search_simple: "1", action: "process", json: "1",
    page_size: String(pageSize), fields: OFF_FIELDS, lc: "it", cc: "it",
  }).toString();
  try {
    const res = await fetch(url, { headers: { "User-Agent": USER_AGENT }, signal: AbortSignal.timeout(8000) });
    if (!res.ok) {
      console.error("off: risposta", res.status);
      return [];
    }
    const json = await res.json() as { products?: OFFProduct[] };
    const items = await Promise.all((json.products ?? []).map(fromOFF));
    return items.filter((i): i is FoodItem => i !== null);
  } catch (error) {
    console.error("off: non raggiungibile", (error as Error).name);
    return [];
  }
}

/** Prodotto per codice a barre, oppure null se non esiste o non ha valori nutrizionali. */
export async function lookupBarcode(code: string): Promise<FoodItem | null> {
  try {
    const res = await fetch(`https://world.openfoodfacts.org/api/v2/product/${code}.json?fields=${OFF_FIELDS}`, {
      headers: { "User-Agent": USER_AGENT }, signal: AbortSignal.timeout(8000),
    });
    if (res.status === 404) return null;
    if (!res.ok) {
      console.error("off: risposta", res.status);
      return null;
    }
    const json = await res.json() as { status?: number; product?: OFFProduct };
    return json.status === 1 && json.product ? await fromOFF({ ...json.product, code }) : null;
  } catch (error) {
    console.error("off: non raggiungibile", (error as Error).name);
    return null;
  }
}
