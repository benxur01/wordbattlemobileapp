-- Sign-in moved from the prototype's Telegram login to Google, which is now
-- the only provider: accounts are keyed on Google's `sub` claim instead of a
-- Telegram user id. Nothing referenced telegram_id except the unique
-- constraint V1 declared inline on it, and dropping the column takes that (and
-- its index) with it.
alter table users add column google_subject varchar(64);

-- Nulls are distinct to a unique index, so the dev-login rows that leave this
-- column empty never collide with one another.
create unique index ux_users_google_subject on users (google_subject);

alter table users drop column telegram_id;
