package uz.wordbattle.friend;

import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import uz.wordbattle.common.ApiException;
import uz.wordbattle.friend.FriendRequestEntity.Status;
import uz.wordbattle.user.User;
import uz.wordbattle.user.UserDto;
import uz.wordbattle.user.UserService;

@Service
public class FriendService {

    private final FriendshipRepository friendships;
    private final FriendRequestRepository requests;
    private final UserService users;
    private final PresenceService presence;

    public FriendService(
            FriendshipRepository friendships,
            FriendRequestRepository requests,
            UserService users,
            PresenceService presence) {
        this.friendships = friendships;
        this.requests = requests;
        this.users = users;
        this.presence = presence;
    }

    public List<FriendDto> friendsOf(Long userId) {
        return friendships.findByUserId(userId).stream()
                .map(f -> users.require(f.getFriendId()))
                .map(friend -> new FriendDto(
                        UserDto.of(friend),
                        presence.isOnline(friend.getId()),
                        presence.isInBattle(friend.getId()),
                        friend.getLastSeenAt()))
                // Online first, then by rating — the list the design shows as
                // "ONLAYN · 3" followed by "OFLAYN".
                .sorted(Comparator.comparing(FriendDto::online).reversed()
                        .thenComparing(d -> -d.user().rating()))
                .toList();
    }

    public Set<Long> friendIds(Long userId) {
        return friendships.findByUserId(userId).stream()
                .map(Friendship::getFriendId)
                .collect(java.util.stream.Collectors.toCollection(HashSet::new));
    }

    public boolean areFriends(Long a, Long b) {
        return friendships.existsByUserIdAndFriendId(a, b);
    }

    public List<FriendRequestDto> incomingRequests(Long userId) {
        Set<Long> myFriends = friendIds(userId);
        return requests.findByToUserIdAndStatus(userId, Status.PENDING).stream()
                .map(request -> {
                    User from = users.require(request.getFromUserId());
                    Set<Long> theirFriends = friendIds(from.getId());
                    theirFriends.retainAll(myFriends);
                    return new FriendRequestDto(
                            request.getId(), UserDto.of(from), theirFriends.size(), request.getCreatedAt());
                })
                .toList();
    }

    public long pendingRequestCount(Long userId) {
        return requests.countByToUserIdAndStatus(userId, Status.PENDING);
    }

    @Transactional
    public FriendRequestEntity sendRequest(Long fromUserId, Long toUserId) {
        if (fromUserId.equals(toUserId)) {
            throw ApiException.badRequest("self_request", "O'zingizga do'stlik so'rovi yubora olmaysiz");
        }
        users.require(toUserId);
        if (areFriends(fromUserId, toUserId)) {
            throw ApiException.conflict("already_friends", "Siz allaqachon do'stsiz");
        }
        // If they already asked us, accept instead of creating a mirror request.
        var reverse = requests.findByFromUserIdAndToUserIdAndStatus(toUserId, fromUserId, Status.PENDING);
        if (reverse.isPresent()) {
            accept(fromUserId, reverse.get().getId());
            return reverse.get();
        }
        return requests.findByFromUserIdAndToUserIdAndStatus(fromUserId, toUserId, Status.PENDING)
                .orElseGet(() -> requests.save(new FriendRequestEntity(fromUserId, toUserId)));
    }

    @Transactional
    public void accept(Long userId, Long requestId) {
        FriendRequestEntity request = requireOwnedRequest(userId, requestId);
        request.resolve(Status.ACCEPTED);
        link(request.getFromUserId(), request.getToUserId());
        link(request.getToUserId(), request.getFromUserId());
    }

    @Transactional
    public void decline(Long userId, Long requestId) {
        requireOwnedRequest(userId, requestId).resolve(Status.DECLINED);
    }

    @Transactional
    public void remove(Long userId, Long friendId) {
        friendships.deleteByUserIdAndFriendId(userId, friendId);
        friendships.deleteByUserIdAndFriendId(friendId, userId);
    }

    private void link(Long userId, Long friendId) {
        if (!friendships.existsByUserIdAndFriendId(userId, friendId)) {
            friendships.save(new Friendship(userId, friendId));
        }
    }

    private FriendRequestEntity requireOwnedRequest(Long userId, Long requestId) {
        FriendRequestEntity request = requests.findById(requestId)
                .orElseThrow(() -> ApiException.notFound("request_not_found", "So'rov topilmadi"));
        if (!request.getToUserId().equals(userId)) {
            throw ApiException.badRequest("not_your_request", "Bu so'rov sizga tegishli emas");
        }
        if (request.getStatus() != Status.PENDING) {
            throw ApiException.conflict("request_resolved", "So'rov allaqachon hal qilingan");
        }
        return request;
    }
}
