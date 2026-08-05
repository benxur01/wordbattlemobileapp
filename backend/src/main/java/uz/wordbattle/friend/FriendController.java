package uz.wordbattle.friend;

import java.util.List;
import java.util.Map;
import org.springframework.web.bind.annotation.*;
import uz.wordbattle.auth.AuthPrincipal;
import uz.wordbattle.auth.CurrentUser;

@RestController
@RequestMapping("/api/friends")
public class FriendController {

    private final FriendService friends;

    public FriendController(FriendService friends) {
        this.friends = friends;
    }

    public record SendRequest(Long userId) {}

    @GetMapping
    public List<FriendDto> list(@CurrentUser AuthPrincipal principal) {
        return friends.friendsOf(principal.userId());
    }

    @GetMapping("/requests")
    public List<FriendRequestDto> requests(@CurrentUser AuthPrincipal principal) {
        return friends.incomingRequests(principal.userId());
    }

    @GetMapping("/requests/count")
    public Map<String, Long> requestCount(@CurrentUser AuthPrincipal principal) {
        return Map.of("count", friends.pendingRequestCount(principal.userId()));
    }

    @PostMapping("/requests")
    public Map<String, Object> send(@CurrentUser AuthPrincipal principal, @RequestBody SendRequest request) {
        var saved = friends.sendRequest(principal.userId(), request.userId());
        return Map.of("id", saved.getId(), "status", saved.getStatus().name());
    }

    @PostMapping("/requests/{id}/accept")
    public void accept(@CurrentUser AuthPrincipal principal, @PathVariable("id") Long id) {
        friends.accept(principal.userId(), id);
    }

    @PostMapping("/requests/{id}/decline")
    public void decline(@CurrentUser AuthPrincipal principal, @PathVariable("id") Long id) {
        friends.decline(principal.userId(), id);
    }

    @DeleteMapping("/{userId}")
    public void remove(@CurrentUser AuthPrincipal principal, @PathVariable("userId") Long userId) {
        friends.remove(principal.userId(), userId);
    }
}
