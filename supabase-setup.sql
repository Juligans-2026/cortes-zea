-- =====================================================================
-- CORTÉS ZEA + LA10  ·  Configuración de Supabase (ejecutar UNA sola vez)
-- Dónde: Supabase > SQL Editor > New query > pegar todo > Run
-- =====================================================================

-- 1) Tabla única de documentos (sirve a las dos apps; la columna "app" las separa)
create table if not exists public.app_docs (
  app         text        not null,              -- 'cortes-zea' | 'la10'
  collection  text        not null,              -- products, customers, sales, bookings...
  id          text        not null,
  data        jsonb       not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  primary key (app, collection, id)
);
create index if not exists app_docs_app_collection_idx on public.app_docs (app, collection);

-- 2) Quién puede entrar a cada app
create table if not exists public.app_members (
  user_id uuid not null references auth.users(id) on delete cascade,
  app     text not null,
  primary key (user_id, app)
);

-- 3) Seguridad (RLS): solo usuarios con sesión y registrados en la app correspondiente
alter table public.app_docs    enable row level security;
alter table public.app_members enable row level security;

drop policy if exists "miembro lee su membresia" on public.app_members;
create policy "miembro lee su membresia" on public.app_members
  for select to authenticated using (user_id = auth.uid());

drop policy if exists "miembros leen docs" on public.app_docs;
create policy "miembros leen docs" on public.app_docs
  for select to authenticated
  using (exists (select 1 from public.app_members m where m.user_id = auth.uid() and m.app = app_docs.app));

drop policy if exists "miembros insertan docs" on public.app_docs;
create policy "miembros insertan docs" on public.app_docs
  for insert to authenticated
  with check (exists (select 1 from public.app_members m where m.user_id = auth.uid() and m.app = app_docs.app));

drop policy if exists "miembros actualizan docs" on public.app_docs;
create policy "miembros actualizan docs" on public.app_docs
  for update to authenticated
  using (exists (select 1 from public.app_members m where m.user_id = auth.uid() and m.app = app_docs.app))
  with check (exists (select 1 from public.app_members m where m.user_id = auth.uid() and m.app = app_docs.app));

drop policy if exists "miembros borran docs" on public.app_docs;
create policy "miembros borran docs" on public.app_docs
  for delete to authenticated
  using (exists (select 1 from public.app_members m where m.user_id = auth.uid() and m.app = app_docs.app));

-- 4) Fecha de actualización automática
create or replace function public.touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;
drop trigger if exists app_docs_touch on public.app_docs;
create trigger app_docs_touch before update on public.app_docs
  for each row execute function public.touch_updated_at();

-- 5) Tiempo real (los cambios de una persona aparecen al instante en las demás)
alter table public.app_docs replica identity full;
do $$ begin
  alter publication supabase_realtime add table public.app_docs;
exception when duplicate_object then null; end $$;

-- =====================================================================
-- 6) DAR ACCESO A UNA PERSONA (repetir por cada empleado)
--    Primero créala en: Authentication > Users > Add user > Create new user
--    (marca "Auto Confirm User"). Luego ejecuta, cambiando correo y app:
-- =====================================================================
-- insert into public.app_members (user_id, app)
-- select id, 'cortes-zea' from auth.users where email = 'correo@empresa.com'
-- on conflict do nothing;
--
-- insert into public.app_members (user_id, app)
-- select id, 'la10' from auth.users where email = 'otro@empresa.com'
-- on conflict do nothing;
