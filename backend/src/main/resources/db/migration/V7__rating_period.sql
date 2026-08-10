-- Glicko-2 reads a rating deviation as "how sure we are about this player",
-- and step 6 of the paper is the half that has been missing: a deviation that
-- has been sitting still for months is not confidence, it is neglect, so the
-- system grows it back out for every rating period a player spends idle --
-- toward the same uncertainty a brand-new account starts with. That needs a
-- clock per player, measured against wordbattle.rating.period-duration.
--
-- Added nullable and only then made not null, because a fresh column with
-- "default now()" would stamp every existing player as having just played,
-- which is precisely the opposite of what the column is for: nobody would ever
-- be inflated for the idle time they had already served.
--
-- Real history wins where there is any. A veteran who played yesterday is not
-- idle since the day they signed up, so the backfill takes the newest
-- rating_history row per player, and falls back to created_at only for accounts
-- that have never settled a rated duel -- the ones who have played nothing but
-- bots, and the ones who have played nothing at all.
alter table users add column rating_period_at timestamptz;

update users u
set rating_period_at = coalesce(
    (select max(rh.recorded_at) from rating_history rh where rh.user_id = u.id),
    u.created_at
);

alter table users alter column rating_period_at set not null;
