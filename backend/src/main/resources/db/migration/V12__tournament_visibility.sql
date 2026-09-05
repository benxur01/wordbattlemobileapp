-- Public and global tournaments: a stranger can join one directly instead of
-- waiting on an admin's guest list or a friend's invite -- see
-- TournamentService#join. visibility is what that endpoint actually gates on:
-- PRIVATE is today's invite-only shape (both FRIEND and ADMIN tournaments
-- start this way, unchanged), PUBLIC is the new self-join door, and a GLOBAL
-- tournament is always PUBLIC. min_rating is only ever set on a GLOBAL row --
-- the rating floor GlobalTournamentScheduler computed the moment it opened
-- the bracket.
alter table tournaments
    add column visibility varchar(16) not null default 'PRIVATE',
    add column kind varchar(16) not null default 'FRIEND',
    add column min_rating double precision;

-- A GLOBAL tournament has no organizer -- it is opened by a scheduled job,
-- not a player or an admin -- so the column that used to name one either way
-- can no longer be not-null.
alter table tournaments
    alter column created_by_admin_id drop not null;
