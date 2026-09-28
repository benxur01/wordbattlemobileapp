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

        // The list is the head of the whole ladder, so the rank each row gets
        // is exactly rankOf its rating — the number the pinned row and the
        // profile show.
        return new Board(ranked(top, me), new Row(userService.rankOf(me), UserDto.of(me), true));
    }

    /** Me plus my friends, ranked among themselves. */
    @GetMapping("/friends")
    public Board friendsBoard(@CurrentUser AuthPrincipal principal) {
        User me = userService.require(principal.userId());

        // One query for the whole friend list rather than one per friend, and
        // through the service so this board and /api/friends read the roster
        // the same way: that one drops deleted accounts, and going straight to
        // the repository here meant a deleted friend would have been ranked as
        // a nameless row with a rating on it.
        //
        // Belt and braces rather than a live bug — deleting an account tears
        // down its friendship rows in both directions before the row itself is
        // anonymised, so an id that reaches here should already be a live
        // player. Should is the operative word: nothing stops a friend request
        // being accepted in the same instant as the deletion and putting the
        // edge back behind it. Either way the two lists cannot drift apart.
        List<User> people = new ArrayList<>();
        people.add(me);
        people.addAll(userService.allByIds(friends.friendIds(me.getId())));
        // Ties in the same order as the global board's, rather than whichever
        // order the roster happened to be read in.
        people.sort(Comparator.comparingDouble(User::getRating).reversed().thenComparing(User::getId));

        List<Row> rows = ranked(people, me);
        return new Board(rows, rows.stream().filter(Row::self).findFirst().orElseThrow());
    }

    /**
     * Numbers players already sorted highest rating first, by competition
     * ranking — 1, 1, 3: a player level with the one above shares their rank,
     * and whoever comes after a tie is numbered by position. That is how
     * {@link UserService#rankOf} counts, one plus everyone strictly higher.
     * The boards used to number by position alone, so two players on the same
     * rating were first and second on the list while the pinned row and the
     * profile called them both first.
     */
    private static List<Row> ranked(List<User> sorted, User me) {
        List<Row> rows = new ArrayList<>(sorted.size());
        long rank = 0;
        for (int i = 0; i < sorted.size(); i++) {
            User user = sorted.get(i);
            if (i == 0 || user.getRating() != sorted.get(i - 1).getRating()) rank = i + 1;
            rows.add(new Row(rank, UserDto.of(user), user.getId().equals(me.getId())));
        }
        return rows;
    }
}
