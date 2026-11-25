-- Fase 9: notifiche push, "Invita un amico", coda delle notifiche.

-- ---------------------------------------------------------------------------
-- Token APNs. Un token appartiene a un solo account: se sullo stesso iPhone si cambia account,
-- il token passa al nuovo (funzione register_push_token). Nessun altro dato del dispositivo.
create table public.push_tokens (
  token text primary key check (token ~ '^[0-9a-f]{64,200}$'),
  user_id uuid not null references auth.users (id) on delete cascade,
  environment text not null check (environment in ('sandbox', 'production')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index push_tokens_user_idx on public.push_tokens (user_id);
alter table public.push_tokens enable row level security;
create policy "token push: lettura dei propri" on public.push_tokens for select to authenticated
  using ((select auth.uid()) = user_id);
revoke all on public.push_tokens from anon, authenticated;
grant select on public.push_tokens to authenticated;
grant select, insert, update, delete on public.push_tokens to service_role;

create function public.register_push_token(p_token text, p_environment text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  insert into public.push_tokens (token, user_id, environment)
  values (lower(p_token), auth.uid(), p_environment)
  on conflict (token) do update
    set user_id = excluded.user_id, environment = excluded.environment, updated_at = now();
  -- Al massimo 10 dispositivi per account: si tengono i più recenti.
  delete from public.push_tokens
  where user_id = auth.uid()
    and token not in (select token from public.push_tokens where user_id = auth.uid() order by updated_at desc limit 10);
end $$;

create function public.unregister_push_token(p_token text)
returns void language sql security definer set search_path = '' as $$
  delete from public.push_tokens where token = lower(p_token) and user_id = auth.uid();
$$;

revoke all on function public.register_push_token(text, text) from public, anon;
revoke all on function public.unregister_push_token(text) from public, anon;
grant execute on function public.register_push_token(text, text) to authenticated;
grant execute on function public.unregister_push_token(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Coda delle notifiche push: la riempiono i trigger, la svuota la funzione push-dispatch (pianificata).
-- Testi fissi scelti dal server: mai dati sanitari nel contenuto della notifica.
create table public.push_outbox (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('referral_reward')),
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  attempts smallint not null default 0
);
create index push_outbox_pending_idx on public.push_outbox (created_at) where sent_at is null;
alter table public.push_outbox enable row level security;
revoke all on public.push_outbox from anon, authenticated;
grant select, insert, update, delete on public.push_outbox to service_role;

-- ---------------------------------------------------------------------------
-- Inviti. Regole in supabase/functions/_shared/referral.ts (con test) e qui sotto per la qualificazione.
create table public.referral_codes (
  user_id uuid primary key references auth.users (id) on delete cascade,
  code text not null unique check (code ~ '^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{8}$'),
  created_at timestamptz not null default now()
);

create table public.referrals (
  referred_id uuid primary key references auth.users (id) on delete cascade,
  referrer_id uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  qualified_at timestamptz,
  -- false se DeviceCheck dice che questo iPhone ha già prodotto un invito valido: l'invito resta ma non conta.
  device_ok boolean not null default true
);
create index referrals_referrer_idx on public.referrals (referrer_id);

-- Lotto di codici offerta Apple monouso importato da App Store Connect (CSV). Solo service_role.
create table public.offer_code_pool (
  code text primary key check (char_length(code) between 4 and 64),
  offer_id text not null,
  expires_at timestamptz not null,
  assigned_to uuid references auth.users (id) on delete set null,
  assigned_at timestamptz
);
create index offer_code_pool_free_idx on public.offer_code_pool (expires_at) where assigned_to is null;

-- Un premio per utente per sempre (chiave primaria): non accumulabile.
create table public.referral_rewards (
  referrer_id uuid primary key references auth.users (id) on delete cascade,
  offer_code text not null,
  assigned_at timestamptz not null default now(),
  expires_at timestamptz not null,
  redeemed_at timestamptz
);

-- Tentativi di inserimento di un codice (limite: 10 al giorno per utente).
create table public.referral_attempts (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  at timestamptz not null default now()
);
create index referral_attempts_user_idx on public.referral_attempts (user_id, at desc);

alter table public.referral_codes enable row level security;
alter table public.referrals enable row level security;
alter table public.offer_code_pool enable row level security;
alter table public.referral_rewards enable row level security;
alter table public.referral_attempts enable row level security;

create policy "codice invito: lettura del proprio" on public.referral_codes for select to authenticated
  using ((select auth.uid()) = user_id);
-- L'amico vede solo la propria riga (chi lo ha invitato non è mostrato in app); chi invita usa i conteggi della funzione.
create policy "inviti: lettura del proprio" on public.referrals for select to authenticated
  using ((select auth.uid()) = referred_id);
create policy "premio: lettura del proprio" on public.referral_rewards for select to authenticated
  using ((select auth.uid()) = referrer_id);

revoke all on public.referral_codes, public.referrals, public.offer_code_pool, public.referral_rewards,
  public.referral_attempts from anon, authenticated;
grant select on public.referral_codes, public.referrals, public.referral_rewards to authenticated;
grant select, insert, update, delete on public.referral_codes, public.referrals, public.offer_code_pool,
  public.referral_rewards, public.referral_attempts to service_role;

-- Assegna il premio a chi invita, se ne ha diritto (stesse regole di decideReward in referral.ts):
-- almeno un invito valido, nessun premio precedente, mai abbonato. Prende il codice libero che scade prima.
create function public.assign_referral_reward(p_referrer uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_code text;
  v_expires timestamptz;
begin
  if p_referrer is null then return false; end if;
  if exists (select 1 from public.referral_rewards where referrer_id = p_referrer) then return false; end if;
  if exists (select 1 from public.subscriptions where user_id = p_referrer) then return false; end if;
  if not exists (select 1 from public.referrals where referrer_id = p_referrer and qualified_at is not null) then
    return false;
  end if;
  select code, least(expires_at, now() + interval '60 days') into v_code, v_expires
  from public.offer_code_pool
  where assigned_to is null and expires_at > now() + interval '7 days'
  order by expires_at
  limit 1
  for update skip locked;
  if v_code is null then
    raise warning 'referral: nessun codice offerta libero';
    return false;
  end if;
  update public.offer_code_pool set assigned_to = p_referrer, assigned_at = now() where code = v_code;
  insert into public.referral_rewards (referrer_id, offer_code, expires_at) values (p_referrer, v_code, v_expires);
  insert into public.push_outbox (user_id, kind) values (p_referrer, 'referral_reward');
  return true;
end $$;
revoke all on function public.assign_referral_reward(uuid) from public, anon, authenticated;
grant execute on function public.assign_referral_reward(uuid) to service_role;

-- Un invito diventa valido al primo pasto dell'amico, con onboarding completato (riga in profiles)
-- e dispositivo non già usato (DeviceCheck). Poi si prova ad assegnare il premio.
create function public.qualify_referral_on_meal()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_referrer uuid;
begin
  update public.referrals r
     set qualified_at = now()
   where r.referred_id = new.user_id
     and r.qualified_at is null
     and r.device_ok
     and exists (select 1 from public.profiles p where p.user_id = new.user_id)
  returning r.referrer_id into v_referrer;
  if v_referrer is not null then
    perform public.assign_referral_reward(v_referrer);
  end if;
  return new;
end $$;
revoke all on function public.qualify_referral_on_meal() from public, anon, authenticated;

create trigger meals_qualify_referral
  after insert on public.meals
  for each row execute function public.qualify_referral_on_meal();

-- ---------------------------------------------------------------------------
-- Irrigidimento dei permessi (controllo di sicurezza della Fase 9, verificato da supabase/tests/security_test.sql).
-- Queste tabelle le scrivono solo le Edge Functions (service_role) o trigger security definer: RLS bloccava già
-- le scritture dell'app, ora non ha nemmeno il permesso SQL.
revoke insert, update, delete, truncate, references, trigger on
  public.subscriptions, public.scan_events, public.ai_events, public.coach_messages, public.consent_events
  from authenticated;
-- coach_messages: l'utente può cancellare la propria conversazione ("Cancella conversazione").
grant delete on public.coach_messages to authenticated;
revoke all on public.food_search_cache from authenticated;
