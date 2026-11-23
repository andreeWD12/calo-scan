-- Permessi per il ruolo `service_role`, usato SOLO dalle Edge Functions (save-profile, delete-account).
-- Nei progetti Supabase recenti le nuove tabelle non ricevono i permessi in automatico: senza questi
-- GRANT la funzione save-profile non può scrivere il profilo (errore 500 "permission denied").
-- La chiave service_role non lascia mai il server.
grant usage on schema public to service_role;
grant select, insert, update, delete on public.profiles, public.professional_plans, public.consents,
  public.consent_events, public.weight_entries to service_role;
