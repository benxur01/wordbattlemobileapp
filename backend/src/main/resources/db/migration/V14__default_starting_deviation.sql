-- New accounts start at Glicko2.MAX_DEVIATION rather than the textbook 350
-- for a totally unrated player, so a fresh account's first result swings
-- 50-75 points -- chess.com's own documented range -- rather than ~160.
-- Hibernate always sends this explicitly on insert (see User#ratingDeviation),
-- so this only matters to a raw-SQL insert that omits the column outright --
-- belt and braces for the same value, not the mechanism that actually sets it.
alter table users
    alter column rating_deviation set default 180;
