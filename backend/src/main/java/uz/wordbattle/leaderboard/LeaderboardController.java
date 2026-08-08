package uz.wordbattle.leaderboard;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import org.springframework.data.domain.PageRequest;
import org.springframework.web.bind.annotation.*;
import uz.wordbattle.auth.AuthPrincipal;
import uz.wordbattle.auth.CurrentUser;
import uz.wordbattle.friend.FriendService;
import uz.wordbattle.user.User;
import uz.wordbattle.user.UserDto;
import uz.wordbattle.user.UserRepository;
import uz.wordbattle.user.UserService;

@RestController
@RequestMapping("/api/leaderboard")
public class LeaderboardController {

    private final UserRepository users;
    private final UserService userService;
    private final FriendService friends;

    public LeaderboardController(UserRepository users, UserService userService, FriendService friends) {
        this.users = users;
        this.userService = userService;
        this.friends = friends;
    }

    public record Row(long rank, UserDto user, boolean self) {}

    /** The list plus the pinned "your position" row at the bottom of the screen. */
    public record Board(List<Row> rows, Row me) {}

    @GetMapping("/global")
    public Board global(
            @CurrentUser AuthPrincipal principal,
            @RequestParam(value = "limit", defaultValue = "50") int limit) {

        User me = userService.require(principal.userId());
        List<User> top = users.topByRating(PageRequest.of(0, Math.max(1, Math.min(limit, 100))));

        List<Row> rows = new ArrayList<>();
        for (int i = 0; i < top.size(); i++) {
            User user = top.get(i);
            rows.add(new Row(i + 1, UserDto.of(user), user.getId().equals(me.getId())));
        }
        return new Board(rows, new Row(userService.rankOf(me), UserDto.of(me), true));
    }

    /** Me plus my friends, ranked among themselves. */
    @GetMapping("/friends")
    public Board friendsBoard(@CurrentUser AuthPrincipal principal) {
        User me = userService.require(principal.userId());

        // One query for the whole friend list rather than one per friend.
        List<User> people = new ArrayList<>();
        people.add(me);
        people.addAll(users.findAllById(friends.friendIds(me.getId())));
        people.sort(Comparator.comparingDouble(User::getRating).reversed());

        List<Row> rows = new ArrayList<>();
        Row mine = null;
        for (int i = 0; i < people.size(); i++) {
            User user = people.get(i);
            boolean self = user.getId().equals(me.getId());
            Row row = new Row(i + 1, UserDto.of(user), self);
            rows.add(row);
            if (self) mine = row;
        }
        return new Board(rows, mine);
    }
}
