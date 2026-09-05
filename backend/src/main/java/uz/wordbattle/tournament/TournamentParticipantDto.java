package uz.wordbattle.tournament;

import uz.wordbattle.user.UserDto;

/**
 * One invited player as the organizer's setup screen renders them — admin's
 * or an ordinary player's, the same shape either way. {@code user} is null
 * only if that account has since been deleted.
 */
public record TournamentParticipantDto(Long userId, UserDto user, String status, Integer seed) {}
