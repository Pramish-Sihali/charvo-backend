-- CharcoalX initial schema.
-- RLS disabled: access is mediated by the FastAPI backend with JWT auth at the application layer.
-- The backend connects via the Supavisor transaction pooler (port 6543), so Supabase RLS policies
-- would not gate this traffic anyway. This is a deliberate architectural choice.

create extension if not exists pgcrypto;

create table if not exists users (
    id            uuid primary key default gen_random_uuid(),
    email         text unique not null,
    password_hash text        not null,
    full_name     text,
    created_at    timestamptz not null default now()
);

create index if not exists ix_users_email on users (email);

alter table users disable row level security;
comment on table users is 'RLS disabled: access mediated by FastAPI backend with JWT auth at the application layer.';

create table if not exists products (
    id          uuid primary key default gen_random_uuid(),
    name        text    not null,
    description text,
    price_cents integer not null check (price_cents >= 0),
    stock       integer not null default 0 check (stock >= 0),
    image_url   text,
    created_at  timestamptz not null default now()
);

alter table products disable row level security;
comment on table products is 'RLS disabled: access mediated by FastAPI backend with JWT auth at the application layer.';

create table if not exists orders (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid    not null references users (id)    on delete cascade,
    product_id  uuid    not null references products (id) on delete restrict,
    quantity    integer not null check (quantity > 0),
    total_cents integer not null check (total_cents >= 0),
    status      text    not null default 'paid',
    created_at  timestamptz not null default now()
);

create index if not exists ix_orders_user_id          on orders (user_id);
create index if not exists ix_orders_created_at_desc  on orders (created_at desc);

alter table orders disable row level security;
comment on table orders is 'RLS disabled: access mediated by FastAPI backend with JWT auth at the application layer.';
