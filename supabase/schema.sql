-- Apply this file to the supplied Supabase project's SQL editor.
create extension if not exists pgcrypto;

create table if not exists public.user_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.bots (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (length(name) between 1 and 100),
  description text not null default '',
  discord_user_id text not null,
  discord_username text not null default '',
  discord_global_name text,
  discord_avatar_url text,
  discord_banner_url text,
  desired_status text not null default 'offline' check (desired_status in ('online','offline')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_id, discord_user_id)
);

-- This table is server-only. Never grant client roles access to it.
create table if not exists public.bot_secrets (
  bot_id uuid primary key references public.bots(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  encrypted_token text not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.commands (
  id uuid primary key default gen_random_uuid(),
  bot_id uuid not null references public.bots(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (name ~ '^[a-z0-9_-]{1,32}$'),
  trigger text not null,
  description text not null default '',
  response text not null default '',
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(bot_id, name)
);

create table if not exists public.workflows (
  id uuid primary key default gen_random_uuid(),
  bot_id uuid not null references public.bots(id) on delete cascade,
  command_id uuid not null unique references public.commands(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  steps jsonb not null default '[]'::jsonb check (jsonb_typeof(steps) = 'array'),
  updated_at timestamptz not null default now()
);

create table if not exists public.bot_variables (
  id uuid primary key default gen_random_uuid(),
  bot_id uuid not null references public.bots(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (length(name) between 1 and 80),
  value jsonb not null default 'null'::jsonb,
  updated_at timestamptz not null default now(),
  unique(bot_id, name)
);

create table if not exists public.bot_logs (
  id bigint generated always as identity primary key,
  bot_id uuid not null references public.bots(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  level text not null default 'info' check (level in ('info','warn','error')),
  message text not null check (length(message) <= 2000),
  created_at timestamptz not null default now()
);

create index if not exists bot_logs_bot_created_idx on public.bot_logs(bot_id, created_at desc);

create table if not exists public.bot_status (
  bot_id uuid primary key references public.bots(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'offline' check (status in ('online','starting','stopping','offline','error')),
  started_at timestamptz,
  last_seen_at timestamptz,
  uptime_seconds bigint not null default 0,
  last_error text,
  updated_at timestamptz not null default now()
);

-- Every client-facing table is scoped to its authenticated owner. Secret rows
-- are deliberately inaccessible to anon/authenticated clients, even their owner.
do $$ declare t text; begin
  foreach t in array array['user_profiles','bots','commands','workflows','bot_variables','bot_logs','bot_status','bot_secrets'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

grant select, insert, update, delete on public.user_profiles, public.bots, public.commands, public.workflows, public.bot_variables, public.bot_logs, public.bot_status to authenticated;
grant usage, select on sequence public.bot_logs_id_seq to authenticated;
grant all on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;

create policy "profile owner" on public.user_profiles for all to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy "bot owner" on public.bots for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "command owner" on public.commands for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "workflow owner" on public.workflows for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "variable owner" on public.bot_variables for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "log owner read" on public.bot_logs for select to authenticated using (owner_id = auth.uid());
create policy "status owner read" on public.bot_status for select to authenticated using (owner_id = auth.uid());

create or replace function public.create_user_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.user_profiles(id) values (new.id) on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile after insert on auth.users
for each row execute procedure public.create_user_profile();
