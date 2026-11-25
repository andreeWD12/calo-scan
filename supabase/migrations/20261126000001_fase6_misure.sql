-- Fase 6: misure corporee (vita, fianchi, petto, braccio, coscia), facoltative.
-- Dati sanitari dell'utente: RLS sul proprietario, cancellazione a cascata con l'account.

create table public.body_measurements (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  date timestamptz not null,
  waist_cm numeric(4, 1) check (waist_cm between 30 and 250),
  hips_cm numeric(4, 1) check (hips_cm between 30 and 250),
  chest_cm numeric(4, 1) check (chest_cm between 30 and 250),
  arm_cm numeric(4, 1) check (arm_cm between 10 and 100),
  thigh_cm numeric(4, 1) check (thigh_cm between 20 and 150),
  created_at timestamptz not null default now(),
  -- Almeno una misura.
  constraint body_measurements_not_empty check (num_nonnulls(waist_cm, hips_cm, chest_cm, arm_cm, thigh_cm) > 0)
);

create index body_measurements_user_date_idx on public.body_measurements (user_id, date desc);

alter table public.body_measurements enable row level security;

create policy "misure: lettura delle proprie"
  on public.body_measurements for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "misure: inserimento delle proprie"
  on public.body_measurements for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "misure: eliminazione delle proprie"
  on public.body_measurements for delete to authenticated
  using ((select auth.uid()) = user_id);

-- Limite anti-abuso: al massimo 1000 rilevazioni per account.
create or replace function public.limit_body_measurements()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.body_measurements where user_id = new.user_id) >= 1000 then
    raise exception 'measurements_full' using errcode = 'P0001';
  end if;
  return new;
end $$;

create trigger body_measurements_limit
  before insert on public.body_measurements
  for each row execute function public.limit_body_measurements();

-- Permessi espliciti: in questo progetto le nuove tabelle non li ricevono in automatico.
revoke all on public.body_measurements from anon;
grant select, insert, delete on public.body_measurements to authenticated;
grant all on public.body_measurements to service_role;
