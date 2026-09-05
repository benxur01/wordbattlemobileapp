-- The 2v2 "team duel" mode: two pairs of friends face off in one word chain,
-- turn order rotating team-a-member-one, team-b-member-one, team-a-member-two,
-- team-b-member-two. Team formation and the matchmaking queue for it are both
-- in-memory only, the same as InviteService and MatchmakingService already are
-- for the 1v1 mode -- what survives a restart is only the settled result,
-- mirrored here from matches/match_words exactly as those two tables are laid
-- out, just with four player slots instead of two.
create table team_matches (
    id                             bigserial   primary key,
    team_a_member_one_id           bigint      not null references users (id),
    team_a_member_two_id           bigint      not null references users (id),
    team_b_member_one_id           bigint      not null references users (id),
    team_b_member_two_id           bigint      not null references users (id),
    team_a_won                     boolean     not null,
    end_reason                     varchar(24) not null,
    chain_length                   integer     not null default 0,
    team_a_member_one_rating_before double precision not null,
    team_a_member_one_rating_after  double precision not null,
    team_a_member_two_rating_before double precision not null,
    team_a_member_two_rating_after  double precision not null,
    team_b_member_one_rating_before double precision not null,
    team_b_member_one_rating_after  double precision not null,
    team_b_member_two_rating_before double precision not null,
    team_b_member_two_rating_after  double precision not null,
    started_at                     timestamptz not null,
    finished_at                    timestamptz not null
);
create index ix_team_matches_a_one on team_matches (team_a_member_one_id, finished_at desc);
create index ix_team_matches_a_two on team_matches (team_a_member_two_id, finished_at desc);
create index ix_team_matches_b_one on team_matches (team_b_member_one_id, finished_at desc);
create index ix_team_matches_b_two on team_matches (team_b_member_two_id, finished_at desc);

create table team_match_words (
    id             bigserial   primary key,
    team_match_id  bigint      not null references team_matches (id) on delete cascade,
    user_id        bigint      references users (id),
    position       integer     not null,
    word           varchar(32) not null,
    spent_ms       integer     not null default 0
);
create index ix_team_match_words_match on team_match_words (team_match_id, position);
