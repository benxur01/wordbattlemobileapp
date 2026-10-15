alter table users
    add column recovery_email varchar(320),
    add column recovery_email_verified_at timestamptz,
    add column pending_recovery_email varchar(320);

create unique index users_verified_recovery_email_idx
    on users (lower(recovery_email))
    where recovery_email_verified_at is not null and deleted_at is null;

create table auth_recovery_codes (
    id bigserial primary key,
    user_id bigint not null references users(id) on delete cascade,
    purpose varchar(32) not null,
    email varchar(320) not null,
    code_hash varchar(64) not null,
    created_at timestamptz not null,
    expires_at timestamptz not null,
    attempts integer not null default 0,
    constraint auth_recovery_codes_user_purpose_unique unique (user_id, purpose)
);

create index auth_recovery_codes_expiry_idx on auth_recovery_codes (expires_at);
