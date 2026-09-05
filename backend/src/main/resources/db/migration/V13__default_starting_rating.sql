-- New accounts start at chess.com's "New to chess" tier rather than the
-- earlier midpoint default. Hibernate always sends 400 explicitly on insert
-- (see User#rating), so this only matters to a raw-SQL insert that omits the
-- column outright -- belt and braces for the same value, not the mechanism
-- that actually sets it.
alter table users
    alter column rating set default 400;
