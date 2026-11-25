-- Test di sicurezza e delle regole del database, eseguiti in CI su un Postgres vuoto
-- (supabase_shim.sql + tutte le migrazioni). Ogni controllo fallito interrompe lo script con un errore.
\set ON_ERROR_STOP 1
\o /dev/null

-- 1. Ogni tabella di public ha RLS attivo.
do $$
declare t text;
begin
  for t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity loop
    raise exception 'RLS non attivo su public.%', t;
  end loop;
end $$;

-- 2. Gli utenti non autenticati (anon) non possono leggere né scrivere nessuna tabella con dati personali.
do $$
declare t text;
begin
  for t in select table_name from information_schema.columns
           where table_schema = 'public' and column_name in ('user_id', 'referrer_id', 'referred_id')
           group by table_name loop
    if has_table_privilege('anon', 'public.' || t, 'select') or has_table_privilege('anon', 'public.' || t, 'insert')
       or has_table_privilege('anon', 'public.' || t, 'update') or has_table_privilege('anon', 'public.' || t, 'delete') then
      raise exception 'anon ha permessi su public.%', t;
    end if;
  end loop;
end $$;

-- 3. Tabelle scritte solo dal server: un utente autenticato non può scriverle.
do $$
declare t text;
begin
  foreach t in array array['subscriptions', 'push_tokens', 'push_outbox', 'referral_codes', 'referrals',
                           'offer_code_pool', 'referral_rewards', 'referral_attempts', 'scan_events', 'ai_events'] loop
    if has_table_privilege('authenticated', 'public.' || t, 'insert') or has_table_privilege('authenticated', 'public.' || t, 'update') then
      raise exception 'authenticated può scrivere public.%', t;
    end if;
  end loop;
  if has_table_privilege('authenticated', 'public.offer_code_pool', 'select') then
    raise exception 'authenticated può leggere i codici offerta';
  end if;
end $$;

-- 4. Le funzioni privilegiate non sono richiamabili dall'app.
do $$
begin
  if has_function_privilege('authenticated', 'public.assign_referral_reward(uuid)', 'execute') then
    raise exception 'assign_referral_reward richiamabile da authenticated';
  end if;
  if has_function_privilege('anon', 'public.register_push_token(text, text)', 'execute') then
    raise exception 'register_push_token richiamabile da anon';
  end if;
end $$;

-- 5. Flusso degli inviti: primo pasto dell'amico → invito valido → premio al referrer → notifica in coda.
insert into auth.users (id) values
  ('00000000-0000-0000-0000-00000000000a'), ('00000000-0000-0000-0000-00000000000b'),
  ('00000000-0000-0000-0000-00000000000c'), ('00000000-0000-0000-0000-00000000000d');
insert into public.offer_code_pool (code, offer_id, expires_at) values ('CODEONE1', 'ref30', now() + interval '90 days');
insert into public.referrals (referred_id, referrer_id) values
  ('00000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000a'),
  ('00000000-0000-0000-0000-00000000000c', '00000000-0000-0000-0000-00000000000a');

-- Senza onboarding (nessun profilo) il pasto non qualifica.
insert into public.meals (id, user_id, type, logged_at, source)
values (gen_random_uuid(), '00000000-0000-0000-0000-00000000000b', 'lunch', now(), 'manual');
do $$ begin
  if exists (select 1 from public.referrals where qualified_at is not null) then raise exception 'qualificato senza onboarding'; end if;
end $$;

insert into public.profiles (user_id, profile, targets) values ('00000000-0000-0000-0000-00000000000b', '{}', '{}');
insert into public.meals (id, user_id, type, logged_at, source)
values (gen_random_uuid(), '00000000-0000-0000-0000-00000000000b', 'dinner', now(), 'manual');
do $$ begin
  if not exists (select 1 from public.referrals where referred_id = '00000000-0000-0000-0000-00000000000b' and qualified_at is not null) then
    raise exception 'invito non qualificato dopo il primo pasto';
  end if;
  if (select offer_code from public.referral_rewards where referrer_id = '00000000-0000-0000-0000-00000000000a') is distinct from 'CODEONE1' then
    raise exception 'premio non assegnato';
  end if;
  if (select count(*) from public.push_outbox where user_id = '00000000-0000-0000-0000-00000000000a') <> 1 then
    raise exception 'notifica del premio non in coda';
  end if;
end $$;

-- Un secondo amico valido non dà un secondo premio (non accumulabile).
insert into public.offer_code_pool (code, offer_id, expires_at) values ('CODETWO2', 'ref30', now() + interval '90 days');
insert into public.profiles (user_id, profile, targets) values ('00000000-0000-0000-0000-00000000000c', '{}', '{}');
insert into public.meals (id, user_id, type, logged_at, source)
values (gen_random_uuid(), '00000000-0000-0000-0000-00000000000c', 'lunch', now(), 'manual');
do $$ begin
  if (select count(*) from public.offer_code_pool where assigned_to is not null) <> 1 then raise exception 'premio accumulato'; end if;
end $$;

-- 6. Isolamento tra utenti (RLS): l'utente B vede solo i propri pasti e non il premio di A.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
do $$ begin
  if exists (select 1 from public.meals where user_id <> '00000000-0000-0000-0000-00000000000b') then raise exception 'RLS: pasti di altri visibili'; end if;
  if exists (select 1 from public.referral_rewards) then raise exception 'RLS: premio di altri visibile'; end if;
end $$;

-- 7. Token push: registrazione, passaggio a un altro account sullo stesso iPhone, rimozione.
select public.register_push_token(repeat('ab', 32), 'sandbox');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000d', false);
select public.register_push_token(repeat('AB', 32), 'production');
reset role;
do $$ begin
  if (select user_id from public.push_tokens where token = repeat('ab', 32)) <> '00000000-0000-0000-0000-00000000000d' then
    raise exception 'token non passato al nuovo account';
  end if;
end $$;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
select public.unregister_push_token(repeat('ab', 32)); -- non suo: non deve cancellarlo
reset role;
do $$ begin
  if not exists (select 1 from public.push_tokens) then raise exception 'token di altri cancellato'; end if;
end $$;

-- 8. Eliminazione dell'account: spariscono anche inviti, premio e token (ON DELETE CASCADE).
delete from auth.users where id = '00000000-0000-0000-0000-00000000000a';
do $$ begin
  if exists (select 1 from public.referral_rewards) or exists (select 1 from public.push_outbox) then
    raise exception 'dati del referrer rimasti dopo l''eliminazione';
  end if;
  if (select count(*) from public.referrals where referrer_id is null) <> 2 then
    raise exception 'referrer non scollegato dagli inviti';
  end if;
end $$;

\o
\echo 'Test di sicurezza del database: tutti superati'
