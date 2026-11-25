-- Fase 5: scanner AI e ricerca alimenti.

-- Registro delle scansioni riuscite, per i limiti giornalieri del piano. Nessuna foto e nessun testo:
-- solo quando, che tipo e quanti alimenti. Scritto solo dalla funzione analyze-food (service_role).
create table public.scan_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('photo', 'description')),
  item_count integer not null check (item_count between 0 and 50),
  created_at timestamptz not null default now()
);

create index scan_events_user_created_idx on public.scan_events (user_id, created_at desc);

alter table public.scan_events enable row level security;

create policy "scansioni: lettura delle proprie" on public.scan_events for select to authenticated
  using ((select auth.uid()) = user_id);

-- Cache delle ricerche negli archivi pubblici (USDA, Open Food Facts): solo dati sugli alimenti,
-- nessun riferimento all'utente. Usata solo dalla funzione food-search; righe oltre 30 giorni ignorate.
create table public.food_search_cache (
  query_key text primary key check (char_length(query_key) <= 120),
  results jsonb not null,
  created_at timestamptz not null default now()
);

alter table public.food_search_cache enable row level security;
-- Nessuna policy: l'app non la legge né la scrive.

revoke all on public.scan_events, public.food_search_cache from anon;
grant select on public.scan_events to authenticated;
grant select, insert, update, delete on public.scan_events, public.food_search_cache to service_role;
