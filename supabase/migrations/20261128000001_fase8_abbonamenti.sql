-- Fase 8: abbonamenti verificati con l'App Store Server API.

-- Un abbonamento Apple (originalTransactionId) appartiene a un solo account. Scritto solo dalle funzioni
-- verify-purchase e app-store-notifications (service_role) dopo aver letto lo stato da Apple.
-- Nessun dato di pagamento: Apple non lo condivide.
create table public.subscriptions (
  original_transaction_id text primary key check (original_transaction_id ~ '^[0-9]{1,30}$'),
  user_id uuid not null references auth.users (id) on delete cascade,
  product_id text not null check (char_length(product_id) <= 100),
  plan text not null check (plan in ('plus', 'pro')),
  status smallint not null check (status between 1 and 5),
  expires_at timestamptz,
  will_renew boolean not null default false,
  environment text not null default 'Production' check (environment in ('Production', 'Sandbox', 'Xcode', 'LocalTesting')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index subscriptions_user_idx on public.subscriptions (user_id);

alter table public.subscriptions enable row level security;

create policy "abbonamenti: lettura dei propri" on public.subscriptions for select to authenticated
  using ((select auth.uid()) = user_id);

revoke all on public.subscriptions from anon;
grant select on public.subscriptions to authenticated;
grant select, insert, update, delete on public.subscriptions to service_role;
