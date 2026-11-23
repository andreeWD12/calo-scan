/**
 * Prova dal vivo degli archivi pubblici (USDA con DEMO_KEY, Open Food Facts). Gira solo in CI:
 * deno run --allow-net --allow-env supabase/functions/_shared/fooddb.live.ts
 * Verifica che i formati delle risposte siano ancora quelli che sappiamo leggere.
 */
import { fromUSDA } from "./foods.ts";
import { bestUSDAMatch, lookupBarcode, searchOFF, searchUSDA } from "./fooddb.ts";

let failed = false;
const check = (label: string, ok: boolean, detail: unknown) => {
  console.log(`${ok ? "OK  " : "FAIL"} ${label}: ${JSON.stringify(detail)}`);
  if (!ok) failed = true;
};

const usda = await searchUSDA("apple raw", 5);
const apple = usda.length ? await fromUSDA(usda[0], "Mela") : null;
check("USDA apple raw", apple !== null && apple.per100g.kcal > 30 && apple.per100g.kcal < 80, apple);

const rice = await searchUSDA("rice white cooked", 5, ["Foundation", "SR Legacy", "Survey (FNDDS)"]);
const riceItem = rice.length ? await fromUSDA(rice[0]) : null;
check("USDA rice cooked", riceItem !== null, riceItem?.per100g);

// La ricerca di Open Food Facts è un servizio volontario spesso sovraccarico: se non risponde
// l'app mostra comunque i risultati USDA, quindi qui è solo un avviso.
const off = await searchOFF("spaghetti", 5);
console.log(`${off.length > 0 ? "OK  " : "WARN"} OFF ricerca spaghetti: ${JSON.stringify(off.slice(0, 2).map((f) => [f.name, f.brand, f.per100g.kcal]))}`);

// Un piatto scomposto come fa lo scanner ("fusilli al pomodoro"): ogni ingrediente deve trovare valori USDA.
for (const [it, en] of [["Fusilli", "pasta cooked"], ["Sugo di pomodoro", "tomato sauce"], ["Olio d'oliva", "olive oil"]]) {
  const m = await bestUSDAMatch(en, it);
  check(`USDA abbinamento ${it}`, m !== null && m.name === it, m?.per100g);
}

const fusilli = await searchOFF("fusilli", 10);
console.log(`${fusilli.length > 0 ? "OK  " : "WARN"} OFF fusilli solo in italiano: ${JSON.stringify(fusilli.map((f) => f.name))}`);

const barcode = await lookupBarcode("8076809513753");
check("OFF codice a barre", barcode !== null && barcode.per100g.kcal > 300, barcode && [barcode.name, barcode.per100g]);

if (failed) Deno.exit(1);
