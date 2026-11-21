-- Resumen en español de cada producto (lo escribe Aguilucho al escanear).
alter table public.pantry_items
  add column if not exists summary text check (char_length(summary) <= 300);
