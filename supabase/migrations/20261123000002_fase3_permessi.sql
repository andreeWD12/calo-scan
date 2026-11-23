-- Permessi espliciti per il ruolo `authenticated` sulle tabelle della Fase 3.
-- Nei progetti Supabase recenti le nuove tabelle possono non essere esposte all'API in automatico:
-- senza questi GRANT ogni richiesta dell'app fallisce con "permission denied", anche con la RLS corretta.
-- La RLS resta il controllo vero: ogni utente vede e modifica solo le proprie righe.
grant usage on schema public to authenticated;
grant select on public.profiles, public.professional_plans, public.consent_events to authenticated;
grant select, insert, update on public.consents to authenticated;
grant select, insert, delete on public.weight_entries to authenticated;

-- Storico dei consensi: niente accesso a OLD durante un INSERT (dove non esiste).
create or replace function public.log_consent_changes() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    insert into public.consent_events (user_id, consent, granted) values
      (new.user_id, 'health_data_processing', new.health_data_processing),
      (new.user_id, 'ai_image_analysis', new.ai_image_analysis),
      (new.user_id, 'product_emails', new.product_emails);
  else
    if new.health_data_processing is distinct from old.health_data_processing then
      insert into public.consent_events (user_id, consent, granted) values (new.user_id, 'health_data_processing', new.health_data_processing);
    end if;
    if new.ai_image_analysis is distinct from old.ai_image_analysis then
      insert into public.consent_events (user_id, consent, granted) values (new.user_id, 'ai_image_analysis', new.ai_image_analysis);
    end if;
    if new.product_emails is distinct from old.product_emails then
      insert into public.consent_events (user_id, consent, granted) values (new.user_id, 'product_emails', new.product_emails);
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;
