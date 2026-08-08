-- Deleting an account has to remove the person without shredding the duels
-- other players took part in: `matches` and `match_words` reference `users`,
-- and an opponent's history is their record too.
--
-- So the row survives with every piece of personal data stripped out --
-- Google identity, nickname, display name, city -- and this column marks it
-- as gone. Nothing but the anonymous shell an old match row points at is left.
alter table users add column deleted_at timestamptz;

-- Leaderboards and search already skip rows with no nickname, which a deleted
-- account no longer has; this index keeps the "is this account still live"
-- checks off a sequential scan.
create index ix_users_deleted_at on users (deleted_at) where deleted_at is not null;
