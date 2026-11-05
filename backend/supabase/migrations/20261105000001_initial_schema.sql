-- =============================================================================
-- THERMO AI — Initial schema
-- File: backend/supabase/migrations/20261105000001_initial_schema.sql
-- Purpose: Core tables, triggers, Row Level Security, AI quota RPC.
-- Apply with: supabase db push   (performed by the implementation agent)
-- =============================================================================

create extension if not exists "pgcrypto";

-- -----------------------------------------------------------------------------
-- Enumerated types (kept in sync with Swift enums in Models/Enums.swift)
-- -----------------------------------------------------------------------------
create type public.biological_sex   as enum ('male', 'female');
create type public.activity_level   as enum ('sedentary', 'light', 'moderate', 'active', 'veryActive');
create type public.weight_goal      as enum ('lose', 'maintain', 'gain');
create type public.bmr_formula      as enum ('mifflinStJeor', 'harrisBenedictRevised', 'katchMcArdle');
create type public.meal_type        as enum ('breakfast', 'lunch', 'dinner', 'snack');
create type public.entry_source     as enum ('manual', 'aiPhoto', 'aiText', 'mealPlan', 'healthKit');

-- -----------------------------------------------------------------------------
-- Shared trigger: maintain updated_at
-- -----------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- profiles: one row per auth user
-- -----------------------------------------------------------------------------
create table public.profiles (
  id                 uuid primary key references auth.users (id) on delete cascade,
  display_name       text        not null default '',
  sex                public.biological_sex,
  birth_date         date,
  height_cm          numeric(5,1) check (height_cm is null or height_cm between 50 and 272),
  activity_level     public.activity_level not null default 'sedentary',
  goal               public.weight_goal    not null default 'maintain',
  goal_rate_kg_week  numeric(3,2) not null default 0.5 check (goal_rate_kg_week between 0 and 1.5),
  body_fat_percent   numeric(4,1) check (body_fat_percent is null or body_fat_percent between 2 and 70),
  bmr_formula        public.bmr_formula not null default 'mifflinStJeor',
  is_pro             boolean     not null default false,   -- server-managed only
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create trigger profiles_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- Auto-create a profile when a user signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', ''));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- -----------------------------------------------------------------------------
-- food_entries: logged foods (soft-deleted for sync)
-- -----------------------------------------------------------------------------
create table public.food_entries (
  id              uuid primary key,                      -- generated on device
  user_id         uuid not null references auth.users (id) on delete cascade,
  consumed_at     timestamptz not null,
  meal_type       public.meal_type not null,
  name            text not null check (char_length(name) between 1 and 200),
  serving_desc    text not null default '',
  grams           numeric(7,1) not null default 0 check (grams >= 0),
  calories        numeric(7,1) not null check (calories >= 0 and calories <= 10000),
  protein_g       numeric(6,1) not null default 0 check (protein_g >= 0),
  carbs_g         numeric(6,1) not null default 0 check (carbs_g >= 0),
  fat_g           numeric(6,1) not null default 0 check (fat_g >= 0),
  fiber_g         numeric(6,1) not null default 0 check (fiber_g >= 0),
  source          public.entry_source not null default 'manual',
  ai_confidence   numeric(3,2) check (ai_confidence is null or ai_confidence between 0 and 1),
  is_deleted      boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index food_entries_user_consumed_idx on public.food_entries (user_id, consumed_at desc);
create index food_entries_user_updated_idx  on public.food_entries (user_id, updated_at);

create trigger food_entries_updated_at
  before update on public.food_entries
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- weight_entries
-- -----------------------------------------------------------------------------
create table public.weight_entries (
  id                uuid primary key,
  user_id           uuid not null references auth.users (id) on delete cascade,
  recorded_at       timestamptz not null,
  weight_kg         numeric(5,2) not null check (weight_kg between 20 and 400),
  body_fat_percent  numeric(4,1) check (body_fat_percent is null or body_fat_percent between 2 and 70),
  is_deleted        boolean not null default false,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index weight_entries_user_recorded_idx on public.weight_entries (user_id, recorded_at desc);
create index weight_entries_user_updated_idx  on public.weight_entries (user_id, updated_at);

create trigger weight_entries_updated_at
  before update on public.weight_entries
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- meal_plans: AI-generated plans stored as validated JSON
-- -----------------------------------------------------------------------------
create table public.meal_plans (
  id            uuid primary key,
  user_id       uuid not null references auth.users (id) on delete cascade,
  title         text not null,
  target_kcal   numeric(6,0) not null,
  plan          jsonb not null,
  is_deleted    boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index meal_plans_user_updated_idx on public.meal_plans (user_id, updated_at);

create trigger meal_plans_updated_at
  before update on public.meal_plans
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- ai_usage: per-user daily AI request counter (written only via RPC)
-- -----------------------------------------------------------------------------
create table public.ai_usage (
  user_id   uuid not null references auth.users (id) on delete cascade,
  day       date not null default (now() at time zone 'utc')::date,
  requests  integer not null default 0,
  primary key (user_id, day)
);

-- Atomically consume one AI request for the calling user.
-- Returns true when the request is allowed, false when the daily limit is reached.
create or replace function public.consume_ai_quota(p_free_limit integer, p_pro_limit integer)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := auth.uid();
  v_pro   boolean;
  v_limit integer;
  v_count integer;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select coalesce(p.is_pro, false) into v_pro from public.profiles p where p.id = v_uid;
  v_limit := case when v_pro then p_pro_limit else p_free_limit end;

  insert into public.ai_usage as u (user_id, day, requests)
  values (v_uid, (now() at time zone 'utc')::date, 1)
  on conflict (user_id, day) do update set requests = u.requests + 1
  returning u.requests into v_count;

  return v_count <= v_limit;
end;
$$;

revoke all on function public.consume_ai_quota(integer, integer) from public, anon;
grant execute on function public.consume_ai_quota(integer, integer) to authenticated;

-- -----------------------------------------------------------------------------
-- Row Level Security
-- (select auth.uid()) is used so Postgres evaluates it once per statement.
-- -----------------------------------------------------------------------------
alter table public.profiles       enable row level security;
alter table public.food_entries   enable row level security;
alter table public.weight_entries enable row level security;
alter table public.meal_plans     enable row level security;
alter table public.ai_usage       enable row level security;

-- profiles
create policy "profiles_select_own" on public.profiles
  for select to authenticated using (id = (select auth.uid()));
create policy "profiles_update_own" on public.profiles
  for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- Users may only update their own non-privileged columns (is_pro is server-managed).
revoke update on public.profiles from authenticated;
grant update (display_name, sex, birth_date, height_cm, activity_level, goal,
              goal_rate_kg_week, body_fat_percent, bmr_formula)
  on public.profiles to authenticated;

-- food_entries
create policy "food_select_own" on public.food_entries
  for select to authenticated using (user_id = (select auth.uid()));
create policy "food_insert_own" on public.food_entries
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "food_update_own" on public.food_entries
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
-- No delete policy: clients soft-delete with is_deleted = true so sync can propagate.

-- weight_entries
create policy "weight_select_own" on public.weight_entries
  for select to authenticated using (user_id = (select auth.uid()));
create policy "weight_insert_own" on public.weight_entries
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "weight_update_own" on public.weight_entries
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- meal_plans
create policy "plans_select_own" on public.meal_plans
  for select to authenticated using (user_id = (select auth.uid()));
create policy "plans_insert_own" on public.meal_plans
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "plans_update_own" on public.meal_plans
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- ai_usage: read-only for the owner; writes only through consume_ai_quota().
create policy "ai_usage_select_own" on public.ai_usage
  for select to authenticated using (user_id = (select auth.uid()));
