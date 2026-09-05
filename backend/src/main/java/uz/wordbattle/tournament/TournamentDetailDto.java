package uz.wordbattle.tournament;

import java.util.List;
import uz.wordbattle.user.UserDto;

/**
 * The whole bracket, exactly as {@code tournament_bracket_screen.dart} draws
 * it. Readable by any signed-in player, participant or not — the bracket is
 * meant to be watched, and nothing in it is worth hiding from a spectator who
 * only wants to look.
 *
 * <p>{@code organizer} is null only if that account has since been deleted —
 * see {@link TournamentInviteDto} for who it can be.
 */
public record TournamentDetailDto(
        Long id,
        String name,
        int size,
        String status,
        int totalRounds,
        List<RoundView> rounds,
        UserDto champion,
        UserDto organizer) {

    public record RoundView(int round, List<MatchView> matches) {}

    /** {@code playerOne}/{@code playerTwo} are null until an earlier round decides them. */
    public record MatchView(
            int slot,
            Long id,
            UserDto playerOne,
            UserDto playerTwo,
            Long winnerUserId,
            String status) {}
}
