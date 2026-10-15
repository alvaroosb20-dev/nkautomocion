-- =====================================================================
--  NK Automoción · Sistema de seguimiento de vehículos
--  Pegar entero en Supabase → proyecto "nkautomocion" → SQL Editor → Run
-- =====================================================================
create extension if not exists pgcrypto with schema extensions;

-- ---------- Ajustes ----------
create table public.app_settings(
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);
insert into public.app_settings(key,value) values
 ('admin_emails','["nkautomocion@gmail.com","alvaroosb20@gmail.com"]'),
 ('notifications','{"enabled":true,"on_status_change":true,"on_ready":true}'),
 ('brand','{"accent":"#f2c637","name":"NK Automoción"}');

-- ---------- Perfiles y roles ----------
create table public.profiles(
  id uuid primary key references auth.users on delete cascade,
  email text,
  full_name text,
  role text not null default 'none' check (role in ('admin','staff','none')),
  created_at timestamptz not null default now()
);

create or replace function public.is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(
    select 1 from public.profiles p join auth.users u on u.id = p.id
    where p.id = auth.uid() and p.role in ('admin','staff') and u.email_confirmed_at is not null)
$$;
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(
    select 1 from public.profiles p join auth.users u on u.id = p.id
    where p.id = auth.uid() and p.role = 'admin' and u.email_confirmed_at is not null)
$$;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles(id, email, role)
  values (new.id, new.email,
    case when exists(
      select 1 from public.app_settings s, jsonb_array_elements_text(s.value) e
      where s.key = 'admin_emails' and lower(e) = lower(new.email)) then 'admin' else 'none' end)
  on conflict (id) do nothing;
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Estados personalizables ----------
create table public.vehicle_statuses(
  key text primary key,
  label text not null,
  description text,
  color text not null default '#f2c637',
  icon text not null default 'dot',
  sort int not null default 0,
  default_progress int check (default_progress between 0 and 100),
  active boolean not null default true
);
insert into public.vehicle_statuses(key,label,description,color,icon,sort,default_progress) values
 ('registrado','Vehículo registrado','Hemos registrado tu vehículo en nuestro sistema.','#8f97a3','clipboard',1,0),
 ('pendiente_revision','Pendiente de revisión','Tu vehículo está en cola para ser revisado por nuestro equipo.','#a78bfa','search',2,10),
 ('iniciado','Proceso iniciado','Hemos comenzado a trabajar en tu vehículo.','#60a5fa','play',3,20),
 ('en_curso','En curso','El trabajo avanza según lo previsto.','#f2c637','wrench',4,40),
 ('fase_final','En fase final','Estamos terminando los últimos detalles.','#fb923c','flag',5,80),
 ('listo','Listo para entregar','Tu vehículo está listo. Ya puedes pasar a recogerlo.','#34d399','check',6,100),
 ('finalizado','Finalizado','El proceso ha finalizado y el vehículo ha sido entregado.','#22c55e','done',7,100),
 ('pausa','En pausa','El proceso está detenido temporalmente. Te informaremos en cuanto se reanude.','#94a3b8','pause',8,null),
 ('incidencia','Incidencia detectada','Hemos detectado una incidencia. Nos pondremos en contacto contigo.','#f87171','alert',9,null);

-- ---------- Vehículos ----------
create table public.vehicles(
  id uuid primary key default gen_random_uuid(),
  plate text not null,
  plate_norm text generated always as (upper(regexp_replace(plate, '[^A-Za-z0-9]', '', 'g'))) stored,
  make_model text not null,
  client_ref text,
  client_phone text,
  client_email text,
  entry_date date not null default current_date,
  description text,
  photo_path text,
  progress int not null default 0 check (progress between 0 and 100),
  status text not null default 'registrado' references public.vehicle_statuses(key) on update cascade,
  eta date,
  public_notes text,
  private_notes text,
  tracking_code text not null default '',
  public_token text not null unique default '',
  notify boolean not null default true,
  archived boolean not null default false,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  updated_by uuid
);
create index vehicles_plate_norm_idx on public.vehicles(plate_norm);
create index vehicles_updated_idx on public.vehicles(updated_at desc);

create or replace function public.gen_tracking_code() returns text
language plpgsql volatile set search_path = public, extensions as $$
declare a text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; r text := ''; b bytea := extensions.gen_random_bytes(6);
begin
  for i in 0..5 loop r := r || substr(a, (get_byte(b, i) % 32) + 1, 1); end loop;
  return r;
end $$;

create or replace function public.vehicles_before() returns trigger
language plpgsql set search_path = public, extensions as $$
begin
  if tg_op = 'INSERT' then
    new.tracking_code := upper(regexp_replace(coalesce(new.tracking_code,''), '[^A-Za-z0-9]', '', 'g'));
    if length(new.tracking_code) < 4 then new.tracking_code := public.gen_tracking_code(); end if;
    new.public_token := encode(extensions.gen_random_bytes(18), 'hex');
    new.created_by := auth.uid();
    new.updated_by := auth.uid();
  else
    new.tracking_code := upper(regexp_replace(coalesce(new.tracking_code,''), '[^A-Za-z0-9]', '', 'g'));
    if length(new.tracking_code) < 4 then new.tracking_code := old.tracking_code; end if;
    new.public_token := old.public_token;
    new.created_at := old.created_at;
    new.created_by := old.created_by;
    new.updated_at := now();
    new.updated_by := auth.uid();
    if new.archived and not old.archived then new.archived_at := now(); end if;
    if not new.archived then new.archived_at := null; end if;
  end if;
  return new;
end $$;
create trigger vehicles_before before insert or update on public.vehicles
  for each row execute function public.vehicles_before();

-- ---------- Historial ----------
create table public.vehicle_updates(
  id bigint generated always as identity primary key,
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  created_at timestamptz not null default now(),
  user_id uuid,
  user_email text,
  kind text not null,
  old_status text,
  new_status text,
  old_progress int,
  new_progress int,
  note text,
  private_note text,
  photo_path text,
  visible_to_client boolean not null default true,
  changes jsonb
);
create index vehicle_updates_vehicle_idx on public.vehicle_updates(vehicle_id, created_at desc);

create or replace function public.vehicles_after() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_note text := nullif(current_setting('app.update_note', true), '');
  v_photo text := nullif(current_setting('app.update_photo', true), '');
  v_priv text := nullif(current_setting('app.private_note', true), '');
  v_changes jsonb; v_kind text; v_visible boolean;
begin
  if tg_op = 'INSERT' then
    insert into public.vehicle_updates(vehicle_id, user_id, user_email, kind, new_status, new_progress, note, photo_path, visible_to_client)
    values (new.id, auth.uid(), auth.jwt() ->> 'email', 'created', new.status, new.progress,
            coalesce(v_note, 'Vehículo registrado en el sistema.'), coalesce(v_photo, new.photo_path), true);
  else
    select jsonb_object_agg(n.key, jsonb_build_object('old', o.value, 'new', n.value)) into v_changes
    from jsonb_each(to_jsonb(new)) n join jsonb_each(to_jsonb(old)) o using (key)
    where n.value is distinct from o.value
      and n.key not in ('updated_at','updated_by','plate_norm','archived_at');
    if v_changes is null and v_note is null and v_photo is null and v_priv is null then return new; end if;
    v_kind := case
      when new.archived and not old.archived then 'archived'
      when old.archived and not new.archived then 'restored'
      when new.status is distinct from old.status or new.progress is distinct from old.progress then 'progress'
      else 'edit' end;
    v_visible := v_kind = 'progress' or v_note is not null or v_photo is not null
      or new.public_notes is distinct from old.public_notes or new.eta is distinct from old.eta;
    insert into public.vehicle_updates(vehicle_id, user_id, user_email, kind, old_status, new_status, old_progress, new_progress,
                                       note, private_note, photo_path, visible_to_client, changes)
    values (new.id, auth.uid(), auth.jwt() ->> 'email', v_kind, old.status, new.status, old.progress, new.progress,
            v_note, v_priv, v_photo, v_visible, v_changes);
  end if;
  begin
    perform realtime.send(jsonb_build_object('at', now()), 'update', 'track-' || new.public_token, false);
  exception when others then null;
  end;
  return new;
end $$;
create trigger vehicles_after after insert or update on public.vehicles
  for each row execute function public.vehicles_after();

-- ---------- Registro de notificaciones ----------
create table public.notifications_log(
  id bigint generated always as identity primary key,
  vehicle_id uuid references public.vehicles(id) on delete cascade,
  channel text not null check (channel in ('whatsapp','email')),
  recipient text,
  message text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);

-- ---------- Intentos de consulta (protección anti fuerza bruta) ----------
create table public.tracking_attempts(
  id bigint generated always as identity primary key,
  plate_norm text,
  ok boolean not null,
  created_at timestamptz not null default now()
);
create index tracking_attempts_idx on public.tracking_attempts(plate_norm, created_at);

-- ---------- Seguridad RLS ----------
alter table public.app_settings enable row level security;
alter table public.profiles enable row level security;
alter table public.vehicle_statuses enable row level security;
alter table public.vehicles enable row level security;
alter table public.vehicle_updates enable row level security;
alter table public.notifications_log enable row level security;
alter table public.tracking_attempts enable row level security;

create policy settings_staff_read on public.app_settings for select to authenticated using (public.is_staff());
create policy settings_admin_write on public.app_settings for update to authenticated using (public.is_admin()) with check (public.is_admin());

create policy profiles_self_read on public.profiles for select to authenticated using (id = auth.uid() or public.is_admin());
create policy profiles_admin_update on public.profiles for update to authenticated using (public.is_admin()) with check (public.is_admin());

create policy statuses_staff_read on public.vehicle_statuses for select to authenticated using (public.is_staff());
create policy statuses_admin_all on public.vehicle_statuses for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy vehicles_staff_select on public.vehicles for select to authenticated using (public.is_staff());
create policy vehicles_staff_insert on public.vehicles for insert to authenticated with check (public.is_staff());
create policy vehicles_staff_update on public.vehicles for update to authenticated using (public.is_staff()) with check (public.is_staff());
create policy vehicles_staff_delete on public.vehicles for delete to authenticated using (public.is_staff());

create policy updates_staff_select on public.vehicle_updates for select to authenticated using (public.is_staff());

create policy notif_staff_select on public.notifications_log for select to authenticated using (public.is_staff());
create policy notif_staff_insert on public.notifications_log for insert to authenticated with check (public.is_staff());

-- ---------- Administrador: actualizar seguimiento ----------
create or replace function public.admin_update_vehicle(
  p_id uuid, p_progress int, p_status text, p_public_notes text, p_eta date,
  p_note text default null, p_private_note text default null, p_photo_path text default null)
returns jsonb language plpgsql security invoker set search_path = public as $$
declare r jsonb;
begin
  if not public.is_staff() then raise exception 'No autorizado' using errcode = '42501'; end if;
  perform set_config('app.update_note', coalesce(p_note, ''), true);
  perform set_config('app.update_photo', coalesce(p_photo_path, ''), true);
  perform set_config('app.private_note', coalesce(p_private_note, ''), true);
  update public.vehicles set
    progress = greatest(0, least(100, p_progress)),
    status = p_status,
    public_notes = nullif(btrim(p_public_notes), ''),
    eta = p_eta,
    private_notes = case when nullif(btrim(p_private_note), '') is null then private_notes
      else concat_ws(E'\n', private_notes,
        to_char(now() at time zone 'Atlantic/Canary', 'DD/MM/YYYY HH24:MI') || ' · ' || coalesce(auth.jwt() ->> 'email', '') || ' · ' || btrim(p_private_note)) end
  where id = p_id
  returning to_jsonb(vehicles.*) into r;
  if r is null then raise exception 'Vehículo no encontrado'; end if;
  return r;
end $$;

-- ---------- Consulta pública (solo datos visibles para el cliente) ----------
create or replace function public._tracking_payload(p_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'token', v.public_token, 'plate', v.plate, 'make_model', v.make_model, 'photo', v.photo_path,
    'entry_date', v.entry_date, 'created_at', v.created_at, 'progress', v.progress, 'eta', v.eta,
    'public_notes', v.public_notes, 'updated_at', v.updated_at, 'archived', v.archived,
    'status', (select jsonb_build_object('key', s.key, 'label', s.label, 'description', s.description, 'color', s.color, 'icon', s.icon)
               from public.vehicle_statuses s where s.key = v.status),
    'timeline', coalesce((
      select jsonb_agg(jsonb_build_object(
        'at', u.created_at, 'progress', u.new_progress, 'note', u.note, 'photo', u.photo_path,
        'status', (select jsonb_build_object('label', s2.label, 'color', s2.color, 'icon', s2.icon) from public.vehicle_statuses s2 where s2.key = u.new_status)
      ) order by u.created_at desc)
      from public.vehicle_updates u where u.vehicle_id = v.id and u.visible_to_client), '[]'::jsonb),
    'brand', (select value from public.app_settings where key = 'brand'),
    'server_time', now()
  ) from public.vehicles v where v.id = p_id
$$;

create or replace function public.get_tracking(p_plate text, p_code text) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_plate text := upper(regexp_replace(coalesce(p_plate, ''), '[^A-Za-z0-9]', '', 'g'));
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_id uuid;
begin
  if length(v_plate) < 4 or length(v_code) < 4 or length(v_plate) > 12 or length(v_code) > 20 then
    return jsonb_build_object('error', 'invalid');
  end if;
  if (select count(*) from public.tracking_attempts where plate_norm = v_plate and not ok and created_at > now() - interval '15 minutes') >= 8
     or (select count(*) from public.tracking_attempts where not ok and created_at > now() - interval '1 minute') >= 60 then
    return jsonb_build_object('error', 'too_many');
  end if;
  select id into v_id from public.vehicles
   where plate_norm = v_plate and tracking_code = v_code
   order by archived, created_at desc limit 1;
  insert into public.tracking_attempts(plate_norm, ok) values (v_plate, v_id is not null);
  delete from public.tracking_attempts where created_at < now() - interval '2 days';
  if v_id is null then return jsonb_build_object('error', 'not_found'); end if;
  return public._tracking_payload(v_id);
end $$;

create or replace function public.get_tracking_by_token(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_id uuid;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{36}$' then return jsonb_build_object('error', 'invalid'); end if;
  select id into v_id from public.vehicles where public_token = p_token;
  if v_id is null then return jsonb_build_object('error', 'not_found'); end if;
  return public._tracking_payload(v_id);
end $$;

-- ---------- Permisos ----------
revoke execute on function public._tracking_payload(uuid) from public, anon, authenticated;
revoke execute on function public.gen_tracking_code() from public, anon, authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.vehicles_before() from public, anon, authenticated;
revoke execute on function public.vehicles_after() from public, anon, authenticated;
revoke execute on function public.admin_update_vehicle(uuid,int,text,text,date,text,text,text) from public, anon;
grant execute on function public.admin_update_vehicle(uuid,int,text,text,date,text,text,text) to authenticated;
revoke execute on function public.is_staff() from public, anon;
revoke execute on function public.is_admin() from public, anon;
grant execute on function public.is_staff() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.get_tracking(text,text) to anon, authenticated;
grant execute on function public.get_tracking_by_token(text) to anon, authenticated;

-- ---------- Tiempo real (panel) ----------
alter publication supabase_realtime add table public.vehicles;

-- ---------- Fotos ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('vehicle-photos', 'vehicle-photos', true, 15728640, array['image/jpeg','image/png','image/webp','image/heic','image/heif'])
on conflict (id) do nothing;
create policy vphotos_staff_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'vehicle-photos' and public.is_staff());
create policy vphotos_staff_update on storage.objects for update to authenticated
  using (bucket_id = 'vehicle-photos' and public.is_staff());
create policy vphotos_staff_delete on storage.objects for delete to authenticated
  using (bucket_id = 'vehicle-photos' and public.is_staff());
create policy vphotos_staff_select on storage.objects for select to authenticated
  using (bucket_id = 'vehicle-photos' and public.is_staff());
