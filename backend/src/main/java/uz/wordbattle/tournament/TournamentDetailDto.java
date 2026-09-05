package uz.wordbattle.tournament;

import java.util.List;
import uz.wordbattle.user.UserDto;

/**
 * The whole bracket, exactly as {@code tournament_bracket_screen.dart} draws
 * it. Readable by any signed-in player, participant or not — the bracket is
 * meant to be watched, and nothing in it is worth hiding from a spectator who
 * only wants to look.
 *
 * <p>{@code organizer} is null if that account has since been deleted, or if
 * there never was one — a {@code GLOBAL} tournament has nobody running it. See
 * {@link TournamentInviteDto} for who it can otherwise be. {@code minRating}
 * is set only when {@code kind} is {@code "global"}.
 */
public record TournamentDetailDto(
        Long id,
        String name,
        int size,
        String status,
        int totalRounds,
        List<RoundView> rounds,
        UserDto champion,
        UserDto organizer,
        String visibility,
        String kind,
        Double minRating) {

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
