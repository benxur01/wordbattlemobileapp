package uz.wordbattle.tournament;

import uz.wordbattle.user.UserDto;

/**
 * "Your tournament match is ready" — pushed live as {@code tournament.match_ready}
 * once both slots of a bracket match are filled, and re-sent on reconnect from
 * {@link TournamentMatchRepository#findReadyFor} since there is no push once the
 * socket has closed.
 */
public record TournamentMatchPromptDto(
        Long tournamentMatchId,
        Long tournamentId,
        String tournamentName,
        int round,
        int totalRounds,
        UserDto opponent) {}
