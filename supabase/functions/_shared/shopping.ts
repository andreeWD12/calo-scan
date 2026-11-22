// Controlli lato server sui suggerimenti della lista della spesa generati dall'AI.
// Il prompt chiede già di escludere gli allergeni; questo filtro è la seconda barriera,
// così un errore del modello non arriva mai all'utente.

export type Allergen =
  | "gluten" | "milk" | "lactose" | "eggs" | "fish" | "shellfish" | "molluscs" | "peanuts"
  | "tree_nuts" | "soy" | "celery" | "mustard" | "sesame" | "sulphites" | "lupin" | "other";

export interface ShoppingSuggestion {
  name: string;
  quantity?: string | null;
  category?: string | null;
  reason?: string | null;
}

/** Parole chiave (in italiano, minuscole) che indicano la presenza dell'allergene. */
export const ALLERGEN_KEYWORDS: Record<Exclude<Allergen, "other">, string[]> = {
  gluten: ["pasta", "pane", "farina", "frumento", "grano", "orzo", "farro", "segale", "couscous", "cracker", "fette biscottate", "biscott", "seitan", "pizza"],
  milk: ["latte", "yogurt", "formagg", "mozzarell", "ricotta", "parmigian", "grana", "burro", "panna", "kefir", "skyr"],
  lactose: ["latte", "yogurt", "formagg", "mozzarell", "ricotta", "burro", "panna"],
  eggs: ["uov", "frittata", "maionese"],
  fish: ["pesce", "salmone", "tonno", "merluzzo", "orata", "branzino", "sgombro", "acciug", "sardin"],
  shellfish: ["gamber", "scampi", "aragost", "granchi", "astice", "crostace"],
  molluscs: ["cozz", "vongol", "calamar", "polpo", "seppi", "ostric"],
  peanuts: ["arachid", "burro di arachidi"],
  tree_nuts: ["mandorl", "noci", "nocciol", "anacardi", "pistacch", "noce", "pinoli", "macadamia"],
  soy: ["soia", "tofu", "tempeh", "edamame"],
  celery: ["sedano"],
  mustard: ["senape"],
  sesame: ["sesamo", "tahin"],
  sulphites: ["vino", "aceto", "frutta secca disidratata"],
  lupin: ["lupin"],
};

const LACTOSE_FREE = ["senza lattosio", "delattosat"];

export function containsAllergen(name: string, allergens: Allergen[]): boolean {
  const n = name.toLowerCase();
  return allergens.some((a) => {
    if (a === "other") return false;
    if (a === "lactose" && LACTOSE_FREE.some((k) => n.includes(k))) return false;
    return ALLERGEN_KEYWORDS[a].some((k) => n.includes(k));
  });
}

/** Rimuove i suggerimenti con allergeni e quelli malformati; massimo 25 prodotti. */
export function filterSuggestions(list: ShoppingSuggestion[], allergens: Allergen[]): ShoppingSuggestion[] {
  return list
    .filter((s) => typeof s?.name === "string" && s.name.trim().length > 0 && [...s.name].length <= 80)
    .filter((s) => !containsAllergen(s.name, allergens))
    .slice(0, 25);
}
