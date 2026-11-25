// Modalità gravidanza: alimenti da evitare o limitare e fabbisogno per trimestre.
// Regole identiche a Pregnancy.swift. Usate per filtrare i suggerimenti dell'AI (lista della spesa,
// coach) quando l'utente ha attivato la modalità gravidanza.
// Fonti: Ministero della Salute / ISS (alimentazione in gravidanza), EFSA (energia 2013, proteine 2012, caffeina 2015).
import { type ActivityLevel, type BodyMetrics, type DailyTargets, type DietPreference, targets } from "./nutrition.ts";

export type PregnancyLevel = "avoid" | "limit";
export type PregnancyRisk =
  | "toxoplasmosis" | "listeria" | "salmonella" | "mercury" | "alcohol" | "caffeine" | "vitamin_a" | "glycyrrhizin";

interface Rule {
  level: PregnancyLevel;
  risk: PregnancyRisk;
  words: string[];
  unless?: string[];
  toxoplasmosisOnly?: boolean;
}

const RULES: Rule[] = [
  { level: "avoid", risk: "alcohol",
    words: ["vino", "birra", "spritz", "prosecco", "spumante", "champagne", "liquor", "grappa", "amaro ",
      "limoncello", "cocktail", "aperitivo alcolico", " rum", " vodka", " whisky", " gin ", "sangria", "alcol"],
    unless: ["analcolic", "senza alcol", "aceto", "0,0", "0.0", "lievito"] },
  { level: "avoid", risk: "toxoplasmosis",
    words: ["carne cruda", "al sangue", "carpaccio di manzo", "carpaccio di carne", "tartare di manzo", "tartare di carne",
      "battuta di", "salsiccia cruda"] },
  { level: "avoid", risk: "toxoplasmosis",
    words: ["prosciutto crudo", "crudo di parma", "san daniele", "salame", "salami", "speck", "coppa", "bresaola",
      "lardo", "culatello", "pancetta", "nduja", "'nduja", "soppressata", "finocchiona", "guanciale"],
    unless: ["cotto", "cotta", "cioccolat", "gelato", "carbonara", "amatriciana", "gricia", "rosolat", "croccant"], toxoplasmosisOnly: true },
  { level: "avoid", risk: "listeria",
    words: ["sushi", "sashimi", "pesce crudo", "crudo di pesce", "carpaccio di pesce", "carpaccio di salmone",
      "carpaccio di tonno", "tartare di salmone", "tartare di tonno", "tartare di pesce", "ostric", "cozze crude",
      "ricci di mare", "ceviche", "alici marinate", "acciughe marinate", "poke"],
    unless: ["cotto", "cotta", "cotti", "vegetarian", "vegan"] },
  { level: "avoid", risk: "listeria",
    words: ["salmone affumicato", "pesce affumicato", "pesce spada affumicato", "tonno affumicato", "trota affumicata"] },
  { level: "avoid", risk: "salmonella",
    words: ["uovo crudo", "uova crude", "tiramis", "zabaion", "maionese fatta in casa", "maionese casalinga",
      "mousse", "crema al mascarpone", "uovo alla coque", "uova alla coque"],
    unless: ["senza uova", "pastorizzat"] },
  { level: "avoid", risk: "listeria",
    words: ["latte crudo", "a latte crudo", "brie", "camembert", "gorgonzola", "roquefort", "taleggio", "erborinat",
      "crosta fiorita", "formaggio fresco non pastorizzato"],
    unless: ["pastorizzat", "cotto", "cotta", "al forno"] },
  { level: "avoid", risk: "vitamin_a", words: ["fegato", "paté", "patè", "pate ", "foie gras"] },
  { level: "avoid", risk: "mercury", words: ["pesce spada", "squalo", "verdesca", "palombo", "smeriglio", "marlin", "luccio"] },
  { level: "avoid", risk: "listeria", words: ["germogli"], unless: ["cotti", "saltati"] },
  { level: "avoid", risk: "caffeine", words: ["energy drink", "red bull", "monster energy", "bevanda energetica"] },
  { level: "limit", risk: "mercury", words: ["tonno"] },
  { level: "limit", risk: "caffeine",
    words: ["caffè", "caffe ", "espresso", "cappuccino", "macchiato", "tè ", "te verde", "tè verde", "tè nero", " cola"],
    unless: ["decaffeinat", "deteinat", "orzo", "ginseng senza"] },
  { level: "limit", risk: "glycyrrhizin", words: ["liquirizia"] },
];

export interface PregnancyFlag { level: PregnancyLevel; risk: PregnancyRisk }

export function checkPregnancyFood(name: string, toxoplasmosisImmune: boolean | null = null): PregnancyFlag | null {
  const text = " " + name.normalize("NFC").toLowerCase().replaceAll("’", "'") + " ";
  for (const r of RULES) {
    if (!r.words.some((w) => text.includes(w)) || (r.unless ?? []).some((w) => text.includes(w))) continue;
    if (r.toxoplasmosisOnly && toxoplasmosisImmune === true) return { level: "limit", risk: "listeria" };
    return { level: r.level, risk: r.risk };
  }
  return null;
}

/** I suggerimenti dell'AI in gravidanza: esclusi gli alimenti da evitare (quelli da limitare restano). */
export function filterForPregnancy<T extends { name: string }>(items: T[], toxoplasmosisImmune: boolean | null): T[] {
  return items.filter((i) => checkPregnancyFood(i.name, toxoplasmosisImmune)?.level !== "avoid");
}

const DAY = 86_400_000;
const dayIndex = (iso: string) => Math.floor(Date.UTC(+iso.slice(0, 4), +iso.slice(5, 7) - 1, +iso.slice(8, 10)) / DAY);

/** Settimane compiute di gravidanza 1…42 dalla data presunta del parto (date "YYYY-MM-DD"). */
export function pregnancyWeek(dueDate: string, today: string): number {
  const days = dayIndex(dueDate) - dayIndex(today);
  return Math.min(Math.max(Math.floor((280 - days) / 7), 1), 42);
}

export function trimester(week: number): 1 | 2 | 3 {
  return week <= 13 ? 1 : week <= 27 ? 2 : 3;
}

export function isValidDueDate(dueDate: string, today: string): boolean {
  const days = dayIndex(dueDate) - dayIndex(today);
  return days >= -14 && days <= 294;
}

/** Data presunta del parto da "settimana N (+ giorni)", settimane 1…41. Identico a `PregnancyInfo.dueDate(week:days:)`. */
export function dueDateFromWeek(week: number, days: number, today: string): string {
  const elapsed = Math.min(Math.max(week, 1), 41) * 7 + Math.min(Math.max(days, 0), 6);
  return new Date((dayIndex(today) + 280 - elapsed) * DAY).toISOString().slice(0, 10);
}

export type PregnancyPhase = "early" | "middle" | "late" | "term";
export interface PregnancyWeekPlan {
  week: number; trimester: 1 | 2 | 3; phase: PregnancyPhase; extraKcal: number; extraProteinG: number;
  nextChangeWeek: number | null; nextExtraKcal: number | null;
}

/** Piano della settimana. Identico a `PregnancyNutrition.weekPlan`. */
export function pregnancyWeekPlan(rawWeek: number): PregnancyWeekPlan {
  const week = Math.min(Math.max(rawWeek, 1), 42);
  const tri = trimester(week);
  const phase: PregnancyPhase = week <= 13 ? "early" : week <= 27 ? "middle" : week <= 36 ? "late" : "term";
  const next = tri === 1 ? 14 : tri === 2 ? 28 : null;
  return { week, trimester: tri, phase, extraKcal: EXTRA_KCAL[tri - 1], extraProteinG: EXTRA_PROTEIN_G[tri - 1],
    nextChangeWeek: next, nextExtraKcal: next === null ? null : (EXTRA_KCAL as readonly number[])[tri] };
}

export const EXTRA_KCAL = [70, 260, 500] as const;
export const EXTRA_PROTEIN_G = [1, 9, 28] as const;

/** Mai in deficit: mantenimento + EFSA per trimestre. Identico a `PregnancyNutrition.targets`. */
export function pregnancyTargets(m: BodyMetrics, activity: ActivityLevel, diet: DietPreference, tri: 1 | 2 | 3): DailyTargets {
  const base = targets(m, activity, "maintain", diet);
  const kcal = base.calorieTarget + EXTRA_KCAL[tri - 1];
  const protein = base.proteinG + EXTRA_PROTEIN_G[tri - 1];
  const fat = Math.max((kcal * 0.3) / 9, m.weightKg * 0.6);
  const carbs = Math.max((kcal - protein * 4 - fat * 9) / 4, 0);
  return {
    bmr: base.bmr, tdee: base.tdee, calorieTarget: Math.round(kcal), proteinG: Math.round(protein),
    carbsG: Math.round(carbs), fatG: Math.round(fat), isAdjustedForSafety: false,
  };
}
