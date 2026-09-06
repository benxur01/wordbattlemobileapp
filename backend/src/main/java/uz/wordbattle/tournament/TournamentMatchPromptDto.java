package uz.wordbattle.tournament;

import uz.wordbattle.user.UserDto;

/**
 * "Your tournament match is ready" — pushed live as {@code tournament.match_ready}
 * once both slots of a bracket match are filled, and re-sent on reconnect from
 * {@link TournamentMatchRepository#findReadyFor} since there is no push once the
 * socket has closed.
 *
 * <p>Everything here is written from one recipient's point of view: {@code
 * opponent} is the other side's primary member, and in a {@code "team"}
 * tournament {@code partner} is the recipient's own teammate and {@code
 * opponentPartner} the fourth player. Both are null when {@code format} is
 * {@code "solo"}, where there are only ever two people in a match.
 */
public record TournamentMatchPromptDto(
        Long tournamentMatchId,
        Long tournamentId,
        String tournamentName,
        int round,
        int totalRounds,
        UserDto opponent,
        String format,
        UserDto partner,
        UserDto opponentPartner) {}
