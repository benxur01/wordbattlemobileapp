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
import org.springframework.dao.OptimisticLockingFailureException;
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
        // Settled before the friendship is written, deliberately: this is the
        // step the two racing calls compete over, and losing it here means the
        // edges below are never attempted at all rather than attempted and
        // rolled back.
        resolve(request, Status.ACCEPTED);
        try {
            link(request.getFromUserId(), request.getToUserId());
            link(request.getToUserId(), request.getFromUserId());
        } catch (DataIntegrityViolationException e) {
            // The unique constraint on the pair, refusing an edge somebody else
            // has just made. The version above rules out the same request being
            // accepted twice, but not two requests that mean the same thing:
            // two players who challenged each other in the same instant hold a
            // pending row each — sendRequest only folds one into the other when
            // it can already see it — and accepting both writes the same two
            // edges. A conflict rather than the 500 this used to be, and this
            // is the truthful one: they are friends, it simply was not this call
            // that made them so.
            throw ApiException.conflict("already_friends", "Siz allaqachon do'stsiz");
        }
    }

    @Transactional
    public void decline(Long userId, Long requestId) {
        resolve(requireOwnedRequest(userId, requestId), Status.DECLINED);
    }

    /**
     * Marks the request answered, and writes it now rather than at commit.
     *
     * <p>The flush is the whole point. Left to the transaction, the version
     * column's refusal arrives after this method has returned and after the
     * controller has, so it surfaces from the commit as a raw
     * {@link OptimisticLockingFailureException} and reaches the player as a 500
     * — the same failure this was meant to fix, moved one layer out. Flushed
     * here it is caught while there is still a call frame to answer in, and the
     * answer is the one {@link #requireOwnedRequest} already gives to a request
     * somebody has dealt with: it has been, a moment ago, by the other tap.
     *
     * <p>The transaction is finished either way — a refused flush marks it
     * rollback-only — so nothing this call had written survives, which is
     * exactly what an accept that lost to a decline must not leave behind.
     */
    private void resolve(FriendRequestEntity request, Status status) {
        request.resolve(status);
        try {
            requests.saveAndFlush(request);
        } catch (OptimisticLockingFailureException e) {
            throw ApiException.conflict("request_resolved", "So'rov allaqachon hal qilingan");
        }
    }

    @Transactional
    public void remove(Long userId, Long friendId) {
        friendships.deleteByUserIdAndFriendId(userId, friendId);
        friendships.deleteByUserIdAndFriendId(friendId, userId);
    }

    /**
     * One direction of a friendship. Written on the spot rather than at commit,
     * so that a constraint refusing it is caught by {@link #accept} instead of
     * escaping the transaction as a 500 — the check above is a courtesy, and the
     * unique index over the pair is what actually decides.
     */
    private void link(Long userId, Long friendId) {
        if (!friendships.existsByUserIdAndFriendId(userId, friendId)) {
            friendships.saveAndFlush(new Friendship(userId, friendId));
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
