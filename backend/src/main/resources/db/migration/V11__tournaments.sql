-- Moneyless single-elimination tournaments: admin-curated brackets with no
-- entry fee and no prize money -- that scope was cut deliberately after a
-- legal discussion about real-money prizes, which is why there is no ledger
-- or payment table anywhere near this feature.
--
-- Three tables mirror the three JPA entities: the tournament itself, who was
-- invited to it and how they answered, and the bracket's matches, one row per
-- slot in every round. Unlike a live duel -- which is only ever in memory,
-- see DuelSession -- a bracket has to survive a reconnect, a relaunch and a
-- server restart, so every bit of it the admin panel or the bracket screen
-- reads is a real row rather than something rebuilt from a socket's memory.
create table tournaments (
    id                    bigserial    primary key,
    name                  varchar(64)  not null,
    size                  int          not null,
    status                varchar(16)  not null,
    created_by_admin_id   bigint       not null references users (id),
    champion_user_id      bigint       references users (id),
    created_at            timestamptz  not null default now(),
    started_at            timestamptz,
    finished_at           timestamptz
);

-- The lobby's "an active tournament exists" banner asks for every row whose
-- status is not COMPLETED, which without this is a sequential scan of a table
-- that otherwise never needs one -- tournaments are rare compared to duels.
create index ix_tournaments_status on tournaments (status);

-- One row per invited player, whether they have answered yet or not. seed is
-- null until the tournament starts -- it is assigned once, from the accepted
-- players' ratings at that moment, and never moves again even if a rating
-- does.
create table tournament_participants (
    id             bigserial    primary key,
    tournament_id  bigint       not null references tournaments (id),
    user_id        bigint       not null references users (id),
    seed           int,
    status         varchar(16)  not null,
    invited_at     timestamptz  not null default now(),
    responded_at   timestamptz
);

-- An admin cannot invite the same player twice into one tournament, and this
-- is also the index the socket handshake's "do I have a pending invite"
-- lookup and the admin panel's participant list both run on.
create unique index ux_tournament_participants_pair on tournament_participants (tournament_id, user_id);
create index ix_tournament_participants_user on tournament_participants (user_id);

-- Every slot of every round, created all at once when the tournament starts
-- so the whole shape of the bracket is known from round one: round 1 is
-- seeded with players immediately, and every later round's two slots start
-- empty and are filled in as their feeder matches are decided. match_id
-- points at the settled duel behind a decided slot -- null until then, and
-- always null for a bye-free bracket's still-pending matches.
create table tournament_matches (
    id                    bigserial    primary key,
    tournament_id         bigint       not null references tournaments (id),
    round                 int          not null,
    slot                  int          not null,
    player_one_user_id    bigint       references users (id),
    player_two_user_id    bigint       references users (id),
    winner_user_id        bigint       references users (id),
    match_id              bigint       references matches (id),
    status                varchar(16)  not null
);

-- The pair every lookup in TournamentService keys on: "the slot fed by round
-- R's matches" during advancement, and "every match of this tournament" for
-- the bracket screen.
create unique index ux_tournament_matches_slot on tournament_matches (tournament_id, round, slot);
