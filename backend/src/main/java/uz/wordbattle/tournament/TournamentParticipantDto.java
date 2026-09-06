package uz.wordbattle.tournament;

import uz.wordbattle.user.UserDto;

/**
 * One seat as the organizer's setup screen renders it — admin's or an ordinary
 * player's, the same shape either way. {@code user} is null only if that
 * account has since been deleted.
 *
 * <p>The three {@code partner...} fields are filled only for a {@code TEAM}
 * tournament's seat, where two people hold it and each answers the invite for
 * themselves: the seat is ready only once {@code status} and {@code
 * partnerStatus} both read {@code "accepted"}.
 */
public record TournamentParticipantDto(
        Long userId,
        UserDto user,
        String status,
        Integer seed,
        Long partnerUserId,
        UserDto partner,
        String partnerStatus) {}
