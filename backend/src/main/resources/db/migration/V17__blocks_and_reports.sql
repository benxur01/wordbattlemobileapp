-- Blocking and reporting. Players write things other players read -- a
-- nickname, a city, every line of duel chat -- and neither store publishes a
-- game like that without a way to stop hearing from somebody and a way to
-- tell somebody who can act on it (App Store guideline 1.2, Play's UGC
-- policy).
--
-- Both tables point at users the way every other table does: a plain
-- reference and no cascade. A users row is never deleted -- V4 keeps it as an
-- anonymous shell -- so nothing here can be left dangling. Account deletion
-- clears the player's blocks along with their friendships, and leaves their
-- reports: those are the moderation record, not the player's to erase.

-- One row per blocker and blocked. The pair is the key, so blocking somebody
-- twice is still one row.
create table user_blocks (
    blocker_id bigint      not null references users (id),
    blocked_id bigint      not null references users (id),
    created_at timestamptz not null default now(),
    primary key (blocker_id, blocked_id),
    constraint ck_user_block_not_self check (blocker_id <> blocked_id)
);

-- The key answers "whom have I blocked". A block silences both directions,
-- so "who has blocked me" is asked just as often -- on a chat line, an invite
-- or a friend request -- and needs an index of its own.
create index ix_user_blocks_blocked on user_blocks (blocked_id, blocker_id);

-- A complaint about a player, and what the panel did about it. details is the
-- reporter's own words, capped at 500 characters by the API. context is where
-- in the app it was filed from (chat, duel, profile), and match_ref the live
-- duel it was filed during, when there was one: a duel's chat is never
-- stored, so those two are what a moderator has to go on.
create table user_reports (
    id          bigserial   primary key,
    reporter_id bigint      not null references users (id),
    reported_id bigint      not null references users (id),
    reason      varchar(32) not null,
    details     text,
    context     varchar(16),
    match_ref   varchar(64),
    status      varchar(16) not null default 'OPEN',
    created_at  timestamptz not null default now(),
    resolved_by bigint      references users (id),
    resolved_at timestamptz,
    constraint ck_user_report_not_self check (reporter_id <> reported_id)
);

-- The panel's queue: one status, newest first.
create index ix_user_reports_status on user_reports (status, id desc);
-- The daily cap counts one reporter's reports since yesterday.
create index ix_user_reports_reporter on user_reports (reporter_id, created_at);
-- Everything ever reported about one player.
create index ix_user_reports_reported on user_reports (reported_id, id desc);
