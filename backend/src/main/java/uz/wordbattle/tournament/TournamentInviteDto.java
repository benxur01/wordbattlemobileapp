package uz.wordbattle.tournament;

import uz.wordbattle.user.UserDto;

/**
 * A tournament invite as the app renders it — pushed live as {@code
 * tournament.invite} while the invited player is connected, and handed back
 * the same shape from {@code GET /api/tournaments/mine} for one who was not.
 *
 * <p>{@code organizer} is whoever created the tournament — an admin or, since
 * {@code TournamentService#createByUser}, an ordinary player organizing one
 * among friends — and is null only if that account has since been deleted.
 *
 * <p>{@code participantStatus} is this recipient's own answer, not their
 * team's: in a {@code "team"} tournament the two people sharing a seat each
 * answer for themselves, and {@code teammate} is the one this invite asks the
 * recipient to play alongside. Null when {@code format} is {@code "solo"}.
 */
public record TournamentInviteDto(
        Long tournamentId,
        String name,
        int size,
        String participantStatus,
        UserDto organizer,
        String format,
        UserDto teammate) {}
