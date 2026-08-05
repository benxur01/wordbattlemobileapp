package uz.wordbattle.friend;

import java.time.Instant;
import uz.wordbattle.user.UserDto;

public record FriendRequestDto(Long id, UserDto user, int mutualFriends, Instant createdAt) {}
