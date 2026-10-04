-- Taste Decoder: initial schema.
--
-- The iOS app is local-first (SwiftData) and mirrors its rows here. Every synced table carries
-- user_id, a server-maintained updated_at (the sync cursor) and deleted_at (soft delete, so other
-- devices learn about deletions). Row-level security keeps every row private to its owner.
-- `collections.visibility` is reserved for sharing with friends later.

-- MARK: - Helpers

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

-- MARK: - Profiles

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger profiles_touch before insert or update on public.profiles
  for each row execute function public.touch_updated_at();

-- Fill the profile from the Google identity on sign-up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, avatar_url)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', new.email),
    coalesce(new.raw_user_meta_data ->> 'avatar_url', new.raw_user_meta_data ->> 'picture')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- MARK: - Synced data

create table public.collections (
  id uuid not null,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null default '',
  domain text not null default 'things',
  verb text not null default 'feel',
  symbol text not null default 'square.stack',
  sort_index integer not null default 0,
  statement text,
  statement_signature text,
  -- Imported collections (e.g. a Pinterest board) carry a summary instead of individual saves.
  source text,
  source_id text,
  source_url text,
  source_item_count integer not null default 0,
  imported_at timestamptz,
  summary text,
  profile jsonb,
  cover_images text[] not null default '{}',
  visibility text not null default 'private' check (visibility in ('private', 'friends')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  -- Keyed per user: demo data uses the same ids on every device and account.
  primary key (user_id, id)
);

create table public.saves (
  id uuid not null,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  -- Soft reference: collections are soft-deleted, and rows may arrive in any order.
  collection_id uuid,
  kind text not null default 'photo',
  title text,
  note text,
  url text,
  image_name text,
  art_style text,
  art_seed integer not null default 0,
  why text,
  decoded_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, id)
);

create table public.tags (
  id uuid not null,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  save_id uuid,
  name text not null,
  key text not null,
  level text not null check (level in ('feeling', 'reference', 'ingredient')),
  status text not null check (status in ('suggested', 'confirmed', 'rejected')),
  source text not null default 'user',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, id)
);

-- Learn cards the user generated or edited (the bundled library isn't stored).
create table public.learn_cards (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  key text not null,
  payload jsonb not null,
  origin text not null default 'generated',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, key)
);

create index collections_user_updated on public.collections (user_id, updated_at);
create index saves_user_updated on public.saves (user_id, updated_at);
create index tags_user_updated on public.tags (user_id, updated_at);
create index learn_cards_user_updated on public.learn_cards (user_id, updated_at);
create index saves_collection on public.saves (user_id, collection_id);
create index tags_save on public.tags (user_id, save_id);

create trigger collections_touch before insert or update on public.collections
  for each row execute function public.touch_updated_at();
create trigger saves_touch before insert or update on public.saves
  for each row execute function public.touch_updated_at();
create trigger tags_touch before insert or update on public.tags
  for each row execute function public.touch_updated_at();
create trigger learn_cards_touch before insert or update on public.learn_cards
  for each row execute function public.touch_updated_at();

-- MARK: - Server-only tables (no client policies: only Edge Functions using the service role can read them)

create table public.pinterest_connections (
  user_id uuid primary key references auth.users (id) on delete cascade,
  access_token text not null,
  refresh_token text,
  expires_at timestamptz,
  refresh_expires_at timestamptz,
  scope text,
  pinterest_username text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger pinterest_connections_touch before insert or update on public.pinterest_connections
  for each row execute function public.touch_updated_at();

create table public.oauth_states (
  state text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  provider text not null,
  created_at timestamptz not null default now()
);

create table public.ai_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null default current_date,
  requests integer not null default 0,
  primary key (user_id, day)
);

-- Atomically counts one Claude request and returns the new total for today.
create or replace function public.record_ai_request(p_user uuid)
returns integer
language sql
security definer
set search_path = public
as $$
  insert into public.ai_usage (user_id, day, requests)
  values (p_user, current_date, 1)
  on conflict (user_id, day) do update set requests = public.ai_usage.requests + 1
  returning requests;
$$;

revoke execute on function public.record_ai_request(uuid) from public, anon, authenticated;

-- MARK: - Row-level security

alter table public.profiles enable row level security;
alter table public.collections enable row level security;
alter table public.saves enable row level security;
alter table public.tags enable row level security;
alter table public.learn_cards enable row level security;
alter table public.pinterest_connections enable row level security;
alter table public.oauth_states enable row level security;
alter table public.ai_usage enable row level security;

create policy "Own profile: read" on public.profiles for select to authenticated using (id = auth.uid());
create policy "Own profile: update" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

create policy "Own collections" on public.collections for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "Own saves" on public.saves for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "Own tags" on public.tags for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "Own learn cards" on public.learn_cards for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Whether Pinterest is connected, without exposing tokens.
create or replace function public.pinterest_status()
returns table (connected boolean, username text)
language sql
security definer
stable
set search_path = public
as $$
  select exists (select 1 from public.pinterest_connections where user_id = auth.uid()),
         (select pinterest_username from public.pinterest_connections where user_id = auth.uid());
$$;

grant execute on function public.pinterest_status() to authenticated;

-- MARK: - Storage: one private folder per user ({user_id}/{file name})

insert into storage.buckets (id, name, public)
values ('images', 'images', false)
on conflict (id) do nothing;

create policy "Own images: read" on storage.objects for select to authenticated
  using (bucket_id = 'images' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "Own images: insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'images' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "Own images: update" on storage.objects for update to authenticated
  using (bucket_id = 'images' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "Own images: delete" on storage.objects for delete to authenticated
  using (bucket_id = 'images' and (storage.foldername(name))[1] = auth.uid()::text);
