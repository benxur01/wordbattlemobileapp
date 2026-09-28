package uz.wordbattle.moderation;

import java.time.Instant;
import uz.wordbattle.user.UserDto;

/** One row of the profile's blocked-players list. */
public record BlockedUserDto(UserDto user, Instant blockedAt) {}
