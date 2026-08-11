-- The admin panel, and the two questions the users table could not answer
-- before it: who may look at somebody else's account, and whose account has
-- been taken away from them.
--
-- is_admin is a column rather than a list of ids in the configuration, because
-- the panel itself hands the role out and a role that lives in a yml file can
-- only be changed by a deploy. The first one still has to come from somewhere:
-- wordbattle.admin.bootstrap-user-id grants this to a single id on startup and
-- does nothing else, so a server with that variable unset creates no admins at
-- all -- which is what an empty default has to mean here.
--
-- banned_at is read on the way in to every authenticated request, beside
-- deleted_at. The token generation an account accepts is looked up only for a
-- row that is neither deleted nor banned, so a ban ends every session the
-- player has open the moment it commits, rather than waiting out the 30 days
-- their token still had to run. A timestamp rather than a boolean for the same
-- reason deleted_at is one: "banned" without "when" is half a record.
alter table users add column is_admin boolean not null default false;
alter table users add column banned_at timestamptz;

-- Same shape and the same reasoning as ix_users_deleted_at in V4. The count on
-- the panel's dashboard asks for every banned account there is, which without
-- this is a sequential scan of the whole table to find the handful of rows the
-- predicate keeps -- and the partial index stores only those.
create index ix_users_banned_at on users (banned_at) where banned_at is not null;

-- Every change the panel makes, with the admin who made it.
--
-- An admin acting on another player's account is the one thing this server does
-- that the player it happens to cannot see and nobody else can reconstruct
-- afterwards: a ban leaves a timestamp but not a name, and a nickname changed
-- by hand leaves nothing whatsoever. So the row is written inside the same
-- transaction as the change it describes -- a log that can be lost while the
-- ban survives would be worse than none, because it would be believed.
--
-- admin_user_id is not null and target_user_id is: an action always has an
-- author, and not every action is about one player.
create table admin_audit_log (
    id             bigserial   primary key,
    admin_user_id  bigint      not null references users (id),
    action         varchar(64) not null,
    target_user_id bigint references users (id),
    detail         text,
    created_at     timestamptz not null default now()
);

-- The list the panel reads today is the newest entries whatever they are, and
-- the primary key already orders that. These two are for the questions asked
-- about a single row rather than about the log: everything done to this player,
-- and everything done by this admin -- which is what anybody actually opens an
-- audit log to find out. Both are also foreign keys, and a foreign key with no
-- index behind it is a scan waiting for the day the referenced row is touched.
create index ix_admin_audit_log_target on admin_audit_log (target_user_id, id desc);
create index ix_admin_audit_log_admin on admin_audit_log (admin_user_id, id desc);
