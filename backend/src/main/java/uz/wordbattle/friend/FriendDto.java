package uz.wordbattle.friend;

import java.time.Instant;
import uz.wordbattle.user.UserDto;

public record FriendDto(UserDto user, boolean online, boolean inBattle, Instant lastSeenAt) {}
