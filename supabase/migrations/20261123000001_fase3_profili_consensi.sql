-- Fase 3: profilo, obiettivi, consensi e peso, con Row Level Security.
-- Ogni tabella è legata a auth.users con ON DELETE CASCADE: cancellare l'utente
-- (funzione delete-account) cancella tutti i suoi dati (art. 17 GDPR, App Store 5.1.1(v)).

-- Profilo e obiettivi. Scritti SOLO dalla funzione save-profile, che li rivalida
-- con le stesse regole dell'app (_shared/profile.ts): il client può solo leggerli.
create table public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  profile jsonb not null,                       -- UserProfile (dati sanitari, art. 9 GDPR)
  targets jsonb not null,                       -- DailyTargets rivalidati dal server
  onboarding_completed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profilo: lettura del proprio"
  on public.profiles for select
  to authenticated
  using ((select auth.uid()) = user_id);

-- Piano del medico o dietista (lettura in Fase 3; scrittura con rivalidazione in Fase 4).
create table public.professional_plans (
  user_id uuid primary key references auth.users (id) on delete cascade,
  plan jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.professional_plans enable row level security;

create policy "piano professionale: lettura del proprio"
  on public.professional_plans for select
  to authenticated
  using ((select auth.uid()) = user_id);

-- Consensi correnti (art. 6, 7 e 9 GDPR). L'utente li legge e li modifica direttamente.
create table public.consents (
  user_id uuid primary key references auth.users (id) on delete cascade,
  health_data_processing boolean not null,
  ai_image_analysis boolean not null default false,
  product_emails boolean not null default false,
  updated_at timestamptz not null default now()
);

alter table public.consents enable row level security;

create policy "consensi: lettura dei propri"
  on public.consents for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "consensi: inserimento dei propri"
  on public.consents for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "consensi: modifica dei propri"
  on public.consents for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- Storico dei consensi: prova di quando sono stati dati o revocati (art. 7(1) GDPR).
-- Scritto solo dal trigger; l'utente può leggere il proprio.
create table public.consent_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  consent text not null check (consent in ('health_data_processing', 'ai_image_analysis', 'product_emails')),
  granted boolean not null,
  at timestamptz not null default now()
);

create index consent_events_user_idx on public.consent_events (user_id, at desc);

alter table public.consent_events enable row level security;

create policy "storico consensi: lettura del proprio"
  on public.consent_events for select to authenticated
  using ((select auth.uid()) = user_id);

create function public.log_consent_changes() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' or new.health_data_processing is distinct from old.health_data_processing then
    insert into public.consent_events (user_id, consent, granted) values (new.user_id, 'health_data_processing', new.health_data_processing);
  end if;
  if tg_op = 'INSERT' or new.ai_image_analysis is distinct from old.ai_image_analysis then
    insert into public.consent_events (user_id, consent, granted) values (new.user_id, 'ai_image_analysis', new.ai_image_analysis);
  end if;
  if tg_op = 'INSERT' or new.product_emails is distinct from old.product_emails then
    insert into public.consent_events (user_id, consent, granted) values (new.user_id, 'product_emails', new.product_emails);
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create trigger consents_log
  before insert or update on public.consents
  for each row execute function public.log_consent_changes();

-- Peso (la prima pesata arriva dall'onboarding).
create table public.weight_entries (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  date timestamptz not null,
  weight_kg numeric(5, 1) not null check (weight_kg between 30 and 350),
  created_at timestamptz not null default now()
);

create index weight_entries_user_date_idx on public.weight_entries (user_id, date desc);

alter table public.weight_entries enable row level security;

create policy "peso: lettura del proprio"
  on public.weight_entries for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "peso: inserimento del proprio"
  on public.weight_entries for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "peso: eliminazione del proprio"
  on public.weight_entries for delete to authenticated
  using ((select auth.uid()) = user_id);

-- Nessun accesso per il ruolo anonimo a queste tabelle.
revoke all on public.profiles, public.professional_plans, public.consents,
              public.consent_events, public.weight_entries from anon;
