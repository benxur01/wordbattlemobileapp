-- 2v2 tournaments: the same single-elimination bracket, with a two-player team
-- occupying each seat instead of one player. Purely additive, and every column
-- below is either defaulted or nullable, so every tournament that already
-- exists stays exactly the SOLO bracket it was.
--
-- The whole design rests on one idea: a team's *primary* member is the id the
-- bracket is seeded, paired, advanced and looked up on, exactly as an
-- individual's id is today. The partner is carried alongside it and read only
-- where a team genuinely differs from a player -- who may be invited, how a
-- seat is rated for seeding, which engine plays the match, and who is told
-- about it.
alter table tournaments
    add column format varchar(16) not null default 'SOLO';

-- user_id is the team's primary member and partner_user_id the teammate; both
-- are null-free only for a TEAM tournament, and partner_user_id stays null for
-- every SOLO seat. partner_status is that teammate's own answer to the invite:
-- a seat counts towards a bracket only once status and partner_status have
-- both been accepted, which is why the teammate needs an answer of their own
-- rather than being enrolled by whoever was named first.
alter table tournament_participants
    add column partner_user_id bigint references users (id),
    add column partner_status varchar(16);

-- The teammate half of ux_tournament_participants_pair: nobody may be seated
-- twice in one bracket, whichever half of a team they were named as. Partial,
-- because every SOLO seat leaves this column null and those are not duplicates
-- of each other.
create unique index ux_tournament_participants_partner
    on tournament_participants (tournament_id, partner_user_id)
    where partner_user_id is not null;

-- The two partner columns mirror the player columns beside them, filled from
-- the same seat when a round is drawn. team_match_id is match_id's counterpart
-- for a TEAM match: the settled duel behind a decided slot lives in
-- team_matches rather than matches, and the two references cannot share one
-- column without pointing a foreign key at the wrong table.
alter table tournament_matches
    add column player_one_partner_user_id bigint references users (id),
    add column player_two_partner_user_id bigint references users (id),
    add column team_match_id bigint references team_matches (id);
