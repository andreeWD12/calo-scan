/**
 * Accesso ai database nutrizionali: USDA FoodData Central (pubblico dominio, chiave USDA_FDC_API_KEY)
 * e Open Food Facts (licenza ODbL, citato nell'app come fonte). Nessun dato dell'utente viene inviato:
 * solo il nome dell'alimento cercato o il codice a barre.
 */
import { type FoodItem, fromOFF, fromUSDA, isLatinName, type OFFProduct, type USDAFood, USDA_DATA_TYPES } from "./foods.ts";

const USER_AGENT = "CaloScan/1.0 (+https://andreewd12.github.io/calo-scan/support/)";
const OFF_FIELDS = "code,product_name,product_name_it,generic_name_it,brands,nutriments,serving_quantity,lang";

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
  // Prima il termine completo, poi uno più generico (es. "fusilli pasta cooked" → "pasta cooked").
  // Niente ripiego su Open Food Facts: i prodotti confezionati hanno spesso valori a crudo (pasta secca),
  // che su un piatto cotto triplicherebbero le calorie. Se non c'è corrispondenza sceglie l'utente.
  for (const query of matchQueries(englishQuery)) {
    const foods = await searchUSDA(query, 5, ["Foundation", "SR Legacy", "Survey (FNDDS)"]);
    for (const f of foods) {
      const item = await fromUSDA(f, italianName);
      if (item) return item;
    }
  }
  return null;
}

/** Varianti di ricerca dalla più precisa alla più generica, senza duplicati. */
export function matchQueries(englishQuery: string): string[] {
  const words = englishQuery.toLowerCase().replace(/[^a-z\s]/g, " ").split(/\s+/).filter(Boolean);
  const variants = [englishQuery.trim(), words.length >= 3 ? words.slice(1).join(" ") : ""];
  return [...new Set(variants.filter((v) => v.length >= 3))];
}

/** Prodotti di Open Food Facts venduti in Italia, cercati per nome. */
export async function searchOFF(query: string, pageSize = 10): Promise<FoodItem[]> {
  // Prima il servizio di ricerca nuovo (search-a-licious), poi quello storico, spesso sovraccarico.
  // Se ne chiedono di più perché poi restano solo i prodotti con il nome in italiano.
  const fetched = await searchOFFNew(query, pageSize * 3) ?? await searchOFFLegacy(query, pageSize * 3) ?? [];
  const italian = fetched.filter(hasItalianName);
  const items = await Promise.all(italian.map(fromOFF));
  return items.filter((i): i is FoodItem => i !== null && isLatinName(i.name)).slice(0, pageSize);
}

/** Prodotto con il nome in italiano: campo product_name_it o lingua principale italiana. */
export function hasItalianName(p: OFFProduct): boolean {
  return Boolean(p.product_name_it?.trim() || p.generic_name_it?.trim()) || p.lang === "it";
}

/** Converte un risultato di search-a-licious (marche come elenco, nomi a volte per lingua). */
export function normalizeOFFHit(hit: Record<string, unknown>): OFFProduct {
  const text = (v: unknown): string | undefined => {
    if (typeof v === "string") return v;
    if (Array.isArray(v)) return v.filter((x) => typeof x === "string").join(", ") || undefined;
    if (v && typeof v === "object") {
      const o = v as Record<string, unknown>;
      return text(o.it ?? o.main ?? o.en ?? Object.values(o)[0]);
    }
    return undefined;
  };
  return {
    code: text(hit.code),
    product_name: text(hit.product_name),
    product_name_it: text(hit.product_name_it),
    generic_name_it: text(hit.generic_name_it),
    brands: text(hit.brands),
    lang: text(hit.lang),
    serving_quantity: hit.serving_quantity as number | string | undefined,
    nutriments: hit.nutriments as OFFProduct["nutriments"],
  };
}

async function searchOFFNew(query: string, pageSize: number): Promise<OFFProduct[] | null> {
  const url = new URL("https://search.openfoodfacts.org/search");
  url.search = new URLSearchParams({ q: query, page_size: String(pageSize), langs: "it", fields: OFF_FIELDS }).toString();
  try {
    const res = await fetch(url, { headers: { "User-Agent": USER_AGENT }, signal: AbortSignal.timeout(6000) });
    if (!res.ok) {
      console.error("off-search: risposta", res.status);
      return null;
    }
    const json = await res.json() as { hits?: Record<string, unknown>[] };
    return Array.isArray(json.hits) ? json.hits.map(normalizeOFFHit) : null;
  } catch (error) {
    console.error("off-search: non raggiungibile", (error as Error).name);
    return null;
  }
}

async function searchOFFLegacy(query: string, pageSize: number): Promise<OFFProduct[] | null> {
  const url = new URL("https://world.openfoodfacts.org/cgi/search.pl");
  url.search = new URLSearchParams({
    search_terms: query, search_simple: "1", action: "process", json: "1",
    page_size: String(pageSize), fields: OFF_FIELDS, lc: "it", cc: "it",
  }).toString();
  try {
    const res = await fetch(url, { headers: { "User-Agent": USER_AGENT }, signal: AbortSignal.timeout(6000) });
    if (!res.ok) {
      console.error("off: risposta", res.status);
      return null;
    }
    const json = await res.json() as { products?: OFFProduct[] };
    return json.products ?? [];
  } catch (error) {
    console.error("off: non raggiungibile", (error as Error).name);
    return null;
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
