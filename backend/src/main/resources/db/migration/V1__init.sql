-- Word Battle schema. Ratings are Glicko-2 (rating / deviation / volatility).

create table users (
    id                bigserial primary key,
    telegram_id       bigint unique,
    nickname          varchar(16),
    display_name      varchar(64),
    city              varchar(64),
    rating            double precision not null default 1200,
    rating_deviation  double precision not null default 350,
    volatility        double precision not null default 0.06,
    streak_days       integer          not null default 0,
    last_played_on    date,
    battles           integer          not null default 0,
    wins              integer          not null default 0,
    longest_chain     integer          not null default 0,
    words_learned     integer          not null default 0,
    created_at        timestamptz      not null default now(),
    last_seen_at      timestamptz
);

-- Nicknames are case-insensitively unique: "Malika_X" must not coexist with "malika_x".
create unique index ux_users_nickname_lower on users (lower(nickname));
create index ix_users_rating on users (rating desc);

-- One row per direction, so "who are my friends" is a single indexed lookup.
create table friendships (
    id         bigserial primary key,
    user_id    bigint      not null references users (id) on delete cascade,
    friend_id  bigint      not null references users (id) on delete cascade,
    created_at timestamptz not null default now(),
    constraint uq_friendship unique (user_id, friend_id),
    constraint ck_friendship_not_self check (user_id <> friend_id)
);
create index ix_friendships_user on friendships (user_id);

create table friend_requests (
    id           bigserial primary key,
    from_user_id bigint      not null references users (id) on delete cascade,
    to_user_id   bigint      not null references users (id) on delete cascade,
    status       varchar(16) not null,
    created_at   timestamptz not null default now(),
    resolved_at  timestamptz,
    constraint ck_request_not_self check (from_user_id <> to_user_id)
);
-- At most one live request per direction; resolved ones stay for history.
create unique index ux_friend_requests_pending
    on friend_requests (from_user_id, to_user_id)
    where status = 'PENDING';
create index ix_friend_requests_to on friend_requests (to_user_id, status);

create table matches (
    id                   bigserial primary key,
    player_one_id        bigint      not null references users (id),
    player_two_id        bigint references users (id),
    bot_opponent         boolean     not null default false,
    winner_id            bigint references users (id),
    end_reason           varchar(24) not null,
    chain_length         integer     not null default 0,
    player_one_rating_before double precision not null,
    player_one_rating_after  double precision not null,
    player_two_rating_before double precision,
    player_two_rating_after  double precision,
    started_at           timestamptz not null,
    finished_at          timestamptz not null
);
create index ix_matches_player_one on matches (player_one_id, finished_at desc);
create index ix_matches_player_two on matches (player_two_id, finished_at desc);

create table match_words (
    id        bigserial primary key,
    match_id  bigint      not null references matches (id) on delete cascade,
    user_id   bigint references users (id),
    position  integer     not null,
    word      varchar(32) not null,
    spent_ms  integer     not null default 0
);
create index ix_match_words_match on match_words (match_id, position);

create table rating_history (
    id          bigserial primary key,
    user_id     bigint      not null references users (id) on delete cascade,
    rating      double precision not null,
    recorded_at timestamptz not null default now()
);
create index ix_rating_history_user on rating_history (user_id, recorded_at);

-- Content for the practice screen (word of the day + meaning).
create table practice_words (
    id      bigserial primary key,
    word    varchar(32) not null unique,
    ipa     varchar(48),
    meaning varchar(255) not null
);
