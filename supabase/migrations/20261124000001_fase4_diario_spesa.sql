-- Fase 4: diario dei pasti e lista della spesa, con Row Level Security.
-- Come in Fase 3: ogni riga è legata a auth.users con ON DELETE CASCADE (art. 17 GDPR) e i permessi
-- vanno concessi esplicitamente (in questo progetto le nuove tabelle non li ricevono in automatico).

-- Numero JSON compreso nell'intervallo; falso (non errore) se il valore non è un numero.
create function public.json_number_between(v jsonb, lo numeric, hi numeric) returns boolean
language sql immutable set search_path = '' as $$
  select case when jsonb_typeof(v) = 'number' then (v #>> '{}')::numeric between lo and hi else false end
$$;

-- Alimenti di un pasto (array di MealItem dell'app). Stessi limiti dell'app: 1–3000 g per alimento,
-- valori per 100 g fisicamente plausibili, al massimo 50 alimenti per pasto.
create function public.meal_items_valid(items jsonb) returns boolean
language sql immutable set search_path = '' as $$
  select jsonb_typeof(items) = 'array'
     and jsonb_array_length(items) <= 50
     and not exists (
       select 1 from jsonb_array_elements(items) as i(item)
       where not (
         jsonb_typeof(item) = 'object'
         and public.json_number_between(item -> 'grams', 1, 3000)
         and jsonb_typeof(item -> 'food') = 'object'
         and char_length(coalesce(item -> 'food' ->> 'name', '')) between 1 and 200
         and public.json_number_between(item -> 'food' -> 'per100g' -> 'kcal', 0, 900)
         and public.json_number_between(item -> 'food' -> 'per100g' -> 'proteinG', 0, 100)
         and public.json_number_between(item -> 'food' -> 'per100g' -> 'carbsG', 0, 100)
         and public.json_number_between(item -> 'food' -> 'per100g' -> 'fatG', 0, 100)
       )
     )
$$;

-- Pasti. L'app scrive direttamente (RLS sul proprietario); i controlli qui sotto rifiutano dati incoerenti.
create table public.meals (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  type text not null check (type in ('breakfast', 'lunch', 'dinner', 'snack')),
  logged_at timestamptz not null,
  source text not null check (source in ('scan', 'description', 'manual', 'plan')),
  scan_id uuid,
  is_cheat_meal boolean not null default false,
  items jsonb not null default '[]' check (public.meal_items_valid(items)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index meals_user_logged_idx on public.meals (user_id, logged_at desc);

alter table public.meals enable row level security;

create policy "pasti: lettura dei propri" on public.meals for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "pasti: inserimento dei propri" on public.meals for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "pasti: modifica dei propri" on public.meals for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "pasti: eliminazione dei propri" on public.meals for delete to authenticated
  using ((select auth.uid()) = user_id);

-- Lista della spesa (manuale, dal piano del professionista o dai suggerimenti accettati).
create table public.shopping_items (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  quantity text check (quantity is null or char_length(quantity) <= 30),
  category text not null check (category in ('produce', 'meat_fish', 'dairy_eggs', 'bakery', 'pantry', 'frozen', 'drinks', 'other')),
  is_checked boolean not null default false,
  source text not null default 'manual' check (source in ('manual', 'plan', 'ai')),
  added_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index shopping_items_user_idx on public.shopping_items (user_id, added_at);

alter table public.shopping_items enable row level security;

create policy "spesa: lettura dei propri" on public.shopping_items for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "spesa: inserimento dei propri" on public.shopping_items for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "spesa: modifica dei propri" on public.shopping_items for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "spesa: eliminazione dei propri" on public.shopping_items for delete to authenticated
  using ((select auth.uid()) = user_id);

-- Al massimo 200 prodotti per utente, come nell'app (ShoppingItem.maxItems).
create function public.limit_shopping_items() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.shopping_items where user_id = new.user_id) >= 200 then
    raise exception 'shopping_list_full' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger shopping_items_limit
  before insert on public.shopping_items
  for each row execute function public.limit_shopping_items();

-- updated_at aggiornato dal database.
create function public.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger meals_touch before update on public.meals
  for each row execute function public.touch_updated_at();
create trigger shopping_items_touch before update on public.shopping_items
  for each row execute function public.touch_updated_at();

-- Permessi: l'app (authenticated) solo sulle proprie righe grazie alla RLS; le Edge Functions (service_role).
revoke all on public.meals, public.shopping_items from anon;
grant select, insert, update, delete on public.meals, public.shopping_items to authenticated;
grant select, insert, update, delete on public.meals, public.shopping_items to service_role;
grant execute on function public.json_number_between(jsonb, numeric, numeric), public.meal_items_valid(jsonb)
  to authenticated, service_role;
