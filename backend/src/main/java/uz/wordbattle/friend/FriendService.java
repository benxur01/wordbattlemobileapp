package uz.wordbattle.friend;

import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.stream.Collectors;
import org.springframework.dao.DataIntegrityViolationException;
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

    /** One query for every friend, not one query per friend. */
    public List<FriendDto> friendsOf(Long userId) {
        return users.allByIds(friendIds(userId)).stream()
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
        List<FriendRequestEntity> pending = requests.findByToUserIdAndStatus(userId, Status.PENDING);
        if (pending.isEmpty()) return List.of();

        // Two queries for the whole list: the senders, and every friendship
        // edge leading out of them. The per-request lookups this replaces made
        // a screen with ten requests thirty round trips.
        Set<Long> senderIds = pending.stream()
                .map(FriendRequestEntity::getFromUserId)
                .collect(Collectors.toSet());
        Map<Long, User> senders = users.allByIds(senderIds).stream()
                .collect(Collectors.toMap(User::getId, user -> user));
        Map<Long, Set<Long>> theirFriends = new HashMap<>();
        for (Friendship edge : friendships.findByUserIdIn(senderIds)) {
            theirFriends.computeIfAbsent(edge.getUserId(), id -> new HashSet<>()).add(edge.getFriendId());
        }

        return pending.stream()
                .map(request -> {
                    User from = senders.get(request.getFromUserId());
                    if (from == null) return null;
                    Set<Long> mutual = new HashSet<>(theirFriends.getOrDefault(from.getId(), Set.of()));
                    mutual.retainAll(myFriends);
                    return new FriendRequestDto(
                            request.getId(), UserDto.of(from), mutual.size(), request.getCreatedAt());
                })
                .filter(Objects::nonNull)
                .toList();
    }

    public long pendingRequestCount(Long userId) {
        return requests.countByToUserIdAndStatus(userId, Status.PENDING);
    }

    @Transactional
    public FriendRequestEntity sendRequest(Long fromUserId, Long toUserId) {
        if (toUserId == null) {
            throw ApiException.badRequest("user_id_required", "Foydalanuvchi ko'rsatilmagan");
        }
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
        var existing = requests.findByFromUserIdAndToUserIdAndStatus(fromUserId, toUserId, Status.PENDING);
        if (existing.isPresent()) {
            return existing.get();
        }
        // The partial index over pending pairs is the real arbiter — a player
        // tapping "add" twice sends two calls that both find nothing pending
        // above and both go on to insert, and the loser used to come back as a
        // 500 "Kutilmagan xatolik" for pressing a button twice.
        //
        // The loser is answered with a conflict rather than handed the winner's
        // row, because by the time the index refuses the write this transaction
        // is already lost: the failed flush marks it rollback-only and the
        // connection will not accept another statement, so reading the request
        // back here would only trade the 500 for a different one at commit. A
        // conflict is what this method already says when the pair is past the
        // request stage, and it is true — the request the player wanted does
        // now exist, it simply was not this call that made it.
        try {
            return requests.saveAndFlush(new FriendRequestEntity(fromUserId, toUserId));
        } catch (DataIntegrityViolationException e) {
            throw ApiException.conflict("request_already_sent", "So'rov allaqachon yuborilgan");
        }
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
