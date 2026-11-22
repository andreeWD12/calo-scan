// Stili alimentari scelti con il coach (Plus e Pro). Catalogo e regole di sicurezza identici a
// EatingStyle.swift. Il modello AI propone SOLO stili di `allowedStyles`: l'output viene filtrato qui
// prima di arrivare all'app, qualunque cosa scriva il modello.

export const EATING_STYLES = [
  "balanced", "mediterranean", "high_protein", "moderate_low_carb", "vegetarian", "vegan",
  "fasting_12_12", "fasting_14_10", "fasting_16_8",
] as const;
export type EatingStyle = (typeof EATING_STYLES)[number];

export const EATING_WINDOW_HOURS: Partial<Record<EatingStyle, number>> = {
  fasting_12_12: 12, fasting_14_10: 10, fasting_16_8: 8,
};

const isFasting = (s: EatingStyle) => EATING_WINDOW_HOURS[s] !== undefined;
const isRestrictive = (s: EatingStyle) => isFasting(s) || s === "moderate_low_carb";

export const EATING_STYLE_SAFETY = { fastingMinimumAge: 18, minimumBMI: 18.5 } as const;

export interface Screening {
  pregnantOrBreastfeeding: boolean;
  diabetesMedication: boolean;
  eatingDisorderHistory: boolean;
  medicalSupervision: boolean;
}

export type EatingStyleBlock =
  | "professional_plan" | "under_age" | "low_bmi" | "pregnancy" | "diabetes_medication"
  | "eating_disorder" | "medical_supervision";

export function styleBlocks(
  style: EatingStyle, ageYears: number, bmi: number, s: Screening, hasProfessionalPlan: boolean,
): EatingStyleBlock[] {
  if (hasProfessionalPlan) return ["professional_plan"];
  const b: EatingStyleBlock[] = [];
  if (isFasting(style)) {
    if (ageYears < EATING_STYLE_SAFETY.fastingMinimumAge) b.push("under_age");
    if (bmi < EATING_STYLE_SAFETY.minimumBMI) b.push("low_bmi");
  }
  if (isRestrictive(style)) {
    if (s.pregnantOrBreastfeeding) b.push("pregnancy");
    if (s.diabetesMedication) b.push("diabetes_medication");
    if (s.eatingDisorderHistory) b.push("eating_disorder");
    if (s.medicalSupervision) b.push("medical_supervision");
  }
  return b;
}

export function allowedStyles(ageYears: number, bmi: number, s: Screening, hasProfessionalPlan: boolean): EatingStyle[] {
  return EATING_STYLES.filter((st) => styleBlocks(st, ageYears, bmi, s, hasProfessionalPlan).length === 0);
}

/** true se il minuto del giorno `minute` cade nella finestra in cui si mangia. */
export function isEatingAt(minute: number, startMinute: number, hours: number): boolean {
  const offset = (((minute - startMinute) % 1440) + 1440) % 1440;
  return offset < hours * 60;
}

// Indicazioni sulla salute non autorizzate (Reg. UE 1924/2006) o allarmanti: se il modello le usa,
// la motivazione viene sostituita con il testo neutro del catalogo.
const FORBIDDEN_CLAIMS = [
  /\bcur[ai]\b/i, /guari/i, /detox/i, /disintossic/i, /brucia[\s-]?grassi/i, /previen/i,
  /\bmalatti/i, /\bterapi/i, /garantit/i, /miracol/i, /dimagri(?:re|sci)\s+(?:velocemente|subito|in\s+\d)/i,
];

export const NEUTRAL_REASON: Record<EatingStyle, string> = {
  balanced: "Un'alimentazione varia con tutti i gruppi di alimenti, facile da seguire ogni giorno.",
  mediterranean: "Verdura, legumi, cereali integrali, pesce e olio d'oliva, con pochi prodotti molto lavorati.",
  high_protein: "Più proteine distribuite nei pasti, utile se ti alleni con regolarità.",
  moderate_low_carb: "Meno carboidrati raffinati, senza eliminarli del tutto.",
  vegetarian: "Niente carne e pesce, con uova e latticini come fonti di proteine.",
  vegan: "Solo alimenti vegetali, con attenzione a proteine, ferro e vitamina B12.",
  fasting_12_12: "Mangi in una finestra di 12 ore, per esempio dalle 8 alle 20.",
  fasting_14_10: "Mangi in una finestra di 10 ore e osservi 14 ore di pausa, notte compresa.",
  fasting_16_8: "Mangi in una finestra di 8 ore e osservi 16 ore di pausa, notte compresa.",
};

const clean = (t: unknown, max: number): string | null => {
  if (typeof t !== "string") return null;
  const s = t.replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim();
  return s ? [...s].slice(0, max).join("") : null;
};

export interface Proposal { style: EatingStyle; reason: string; firstSteps: string[] }

/** Filtra l'output del modello: solo stili ammessi, al massimo 3, senza doppioni né claim vietati. */
export function sanitizeProposals(raw: unknown, allowed: EatingStyle[]): Proposal[] {
  if (!Array.isArray(raw)) return [];
  const out: Proposal[] = [];
  for (const r of raw) {
    const style = (r as { style?: unknown })?.style as EatingStyle;
    if (!allowed.includes(style) || out.some((p) => p.style === style)) continue;
    let reason = clean((r as { reason?: unknown }).reason, 300) ?? NEUTRAL_REASON[style];
    const steps = Array.isArray((r as { firstSteps?: unknown }).firstSteps)
      ? ((r as { firstSteps: unknown[] }).firstSteps.map((x) => clean(x, 120)).filter(Boolean) as string[]).slice(0, 3)
      : [];
    const claims = (t: string) => FORBIDDEN_CLAIMS.some((re) => re.test(t));
    if (claims(reason)) reason = NEUTRAL_REASON[style];
    out.push({ style, reason, firstSteps: steps.filter((t) => !claims(t)) });
    if (out.length === 3) break;
  }
  return out;
}
