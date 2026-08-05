-- Every distinct word a player has ever played, so "yangi so'z" on the win
-- screen and the words_learned counter are real numbers rather than guesses.
create table user_words (
    user_id       bigint      not null references users (id) on delete cascade,
    word          varchar(32) not null,
    first_used_at timestamptz not null default now(),
    primary key (user_id, word)
);
