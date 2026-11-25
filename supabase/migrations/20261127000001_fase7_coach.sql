-- Fase 7: AI Nutrition Coach.

-- Conversazione con il coach (dato sanitario, art. 9 GDPR). Scritta solo dalla funzione coach-chat
-- (service_role); l'utente la legge e può cancellarla. Si cancella con l'account (on delete cascade).
create table public.coach_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null check (role in ('user', 'assistant')),
  text text not null check (char_length(text) between 1 and 4000),
  created_at timestamptz not null default now()
);

create index coach_messages_user_created_idx on public.coach_messages (user_id, created_at desc);

alter table public.coach_messages enable row level security;

create policy "coach: lettura dei propri messaggi" on public.coach_messages for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "coach: cancellazione dei propri messaggi" on public.coach_messages for delete to authenticated
  using ((select auth.uid()) = user_id);

-- Utilizzo delle funzioni AI per i limiti del piano: nessun testo, solo quando e cosa.
-- Separato dai messaggi, così cancellare la conversazione non azzera il limite di oggi.
create table public.ai_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('coach', 'eating_styles', 'shopping')),
  created_at timestamptz not null default now()
);

create index ai_events_user_kind_created_idx on public.ai_events (user_id, kind, created_at desc);

alter table public.ai_events enable row level security;

create policy "utilizzo AI: lettura del proprio" on public.ai_events for select to authenticated
  using ((select auth.uid()) = user_id);

revoke all on public.coach_messages, public.ai_events from anon;
grant select, delete on public.coach_messages to authenticated;
grant select on public.ai_events to authenticated;
grant select, insert, update, delete on public.coach_messages, public.ai_events to service_role;
