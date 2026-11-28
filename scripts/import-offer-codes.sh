#!/usr/bin/env bash
# Prepara l'importazione dei codici offerta monouso di App Store Connect nel lotto degli inviti (offer_code_pool).
#
# Uso:  scripts/import-offer-codes.sh <file scaricato da App Store Connect> <scadenza AAAA-MM-GG> [offer_id]
# Es.:  scripts/import-offer-codes.sh ~/Downloads/ref30.csv 2027-05-28
#
# Crea accanto al file di Apple un file .sql da incollare in Supabase › SQL Editor › Run. Il file:
#  - aggiunge i codici (quelli già presenti vengono ignorati, quindi si può rieseguire senza danni);
#  - assegna subito il premio a chi lo stava aspettando (con notifica push), invece di aspettare
#    che riapra "Invita un amico".
# Nessun codice viene inviato altrove: lo script lavora solo sui file locali.
set -euo pipefail

src=${1:-}
expiry=${2:-}
offer=${3:-ref30}

if [[ -z $src || -z $expiry ]]; then
  sed -n '4,5p' "$0" | sed 's/^# //'
  exit 1
fi
[[ -f $src ]] || { echo "File non trovato: $src" >&2; exit 1; }
[[ $expiry =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "Scadenza nel formato AAAA-MM-GG, es. 2027-05-28" >&2; exit 1; }
[[ $offer =~ ^[A-Za-z0-9_-]{1,64}$ ]] || { echo "offer_id non valido: $offer" >&2; exit 1; }
if [[ ! $expiry > $(date -u +%F) ]]; then
  echo "La scadenza $expiry è già passata." >&2
  exit 1
fi

# Un codice Apple è fatto di lettere maiuscole e cifre. Si prende ogni campo che ha quella forma, con almeno
# una lettera e una cifra, così intestazioni, date e numeri non finiscono nel lotto, qualunque sia il formato del file.
codes=$(tr -d '\r"' < "$src" | tr ',;\t ' '\n\n\n\n' \
  | grep -E '^[A-Z0-9]{8,32}$' | grep '[A-Z]' | grep '[0-9]' | sort -u || true)
count=$(printf '%s\n' "$codes" | grep -c . || true)
if [[ $count -eq 0 ]]; then
  echo "Nessun codice trovato in $src. È il file dei codici monouso scaricato da App Store Connect?" >&2
  exit 1
fi

out="${src%.*}-import.sql"
# Scadenza a mezzanotte UTC del giorno indicato: qualche ora prima di quella di Apple, mai dopo.
expires_at="${expiry}T00:00:00Z"
{
  echo "-- $count codici offerta '$offer', scadenza $expiry. Generato da scripts/import-offer-codes.sh."
  echo "insert into public.offer_code_pool (code, offer_id, expires_at) values"
  printf '%s\n' "$codes" | awk -v o="$offer" -v e="$expires_at" -v n="$count" \
    '{ printf "  (\x27%s\x27, \x27%s\x27, \x27%s\x27)%s\n", $0, o, e, (NR < n ? "," : "") }'
  echo "on conflict (code) do nothing;"
  echo
  echo "-- Premi in attesa (lotto vuoto finora): assegnati ora, con notifica. La funzione rispetta le regole"
  echo "-- (un premio per persona, mai stato abbonato, invito valido)."
  echo "select count(*) filter (where public.assign_referral_reward(referrer_id)) as premi_assegnati_ora"
  echo "from (select distinct referrer_id from public.referrals where qualified_at is not null) r;"
} > "$out"

echo "Codici trovati: $count (confrontali con il numero generato in App Store Connect)."
echo "Primo: $(printf '%s\n' "$codes" | head -1)   Ultimo: $(printf '%s\n' "$codes" | tail -1)"
echo "File pronto: $out"
echo "Aprilo, copia tutto in Supabase › SQL Editor e premi Run."
