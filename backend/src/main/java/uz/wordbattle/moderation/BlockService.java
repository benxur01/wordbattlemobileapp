package uz.wordbattle.moderation;

import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import uz.wordbattle.common.ApiException;
import uz.wordbattle.friend.FriendRequestEntity.Status;
import uz.wordbattle.friend.FriendRequestRepository;
import uz.wordbattle.friend.FriendshipRepository;
import uz.wordbattle.user.User;
import uz.wordbattle.user.UserDto;
import uz.wordbattle.user.UserService;

/**
 * Players blocking one another.
 *
 * <p>A block is placed by one player and felt by both: whichever of the two
 * placed it, chat and reactions stop passing between them, neither can
 * challenge, team up with or befriend the other, the queue does not pair them,
 * and neither turns up in the other's search. A block the blocked player could
 * walk round from their own side would protect nobody, and nothing tells them
 * which of the two it was — every refusal reads the same either way.
 *
 * <p>The checks are a query each, asked only where two particular players are
 * about to meet — a chat line, an invite, a candidate pair in the queue —
 * rather than kept in a cache that would have to be told about every block
 * and unblock to stay right.
 */
@Service
public class BlockService {

    private final UserBlockRepository blocks;
    private final UserService users;
    private final FriendshipRepository friendships;
    private final FriendRequestRepository friendRequests;
    private final TransactionTemplate transactions;

    public BlockService(
            UserBlockRepository blocks,
            UserService users,
            FriendshipRepository friendships,
            FriendRequestRepository friendRequests,
            PlatformTransactionManager transactionManager) {
        this.blocks = blocks;
        this.users = users;
        this.friendships = friendships;
        this.friendRequests = friendRequests;
        this.transactions = new TransactionTemplate(transactionManager);
    }

    /**
     * Blocks {@code blockedId} for {@code blockerId}, and ends whatever stood
     * between the two: the friendship in both directions, and a request still
     * waiting in either — left pending, it would sit in one player's list with
     * an accept button that brings the friendship straight back.
     *
     * <p>Blocking somebody already blocked changes nothing, not even when the
     * block was placed.
     */
    public void block(Long blockerId, Long blockedId) {
        if (blockerId.equals(blockedId)) {
            throw ApiException.badRequest("self_block", "O'zingizni bloklay olmaysiz");
        }
        users.require(blockedId);
        try {
            transactions.executeWithoutResult(status -> {
                if (blocks.existsById(new UserBlock.Key(blockerId, blockedId))) return;
                blocks.saveAndFlush(new UserBlock(blockerId, blockedId));
                friendships.deleteByUserIdAndFriendId(blockerId, blockedId);
                friendships.deleteByUserIdAndFriendId(blockedId, blockerId);
                friendRequests.deleteByFromUserIdAndToUserIdAndStatus(blockerId, blockedId, Status.PENDING);
                friendRequests.deleteByFromUserIdAndToUserIdAndStatus(blockedId, blockerId, Status.PENDING);
            });
        } catch (DataIntegrityViolationException e) {
            // The primary key refusing a second insert of the same pair: a
            // double tap, both halves of which found no block above. The one
            // that won has written the block and ended the friendship, which
            // is everything this call was asked to do.
        }
    }

    /** Lifts the block. The friendship it ended stays ended. */
    public void unblock(Long blockerId, Long blockedId) {
        blocks.deleteById(new UserBlock.Key(blockerId, blockedId));
    }

    /** Everyone the player has blocked, most recent first. */
    public List<BlockedUserDto> blockedBy(Long blockerId) {
        List<UserBlock> rows = blocks.findByBlockerIdOrderByCreatedAtDesc(blockerId);
        Map<Long, User> live = users.allByIds(rows.stream().map(UserBlock::getBlockedId).toList()).stream()
                .collect(Collectors.toMap(User::getId, user -> user));
        return rows.stream()
                .filter(row -> live.containsKey(row.getBlockedId()))
                .map(row -> new BlockedUserDto(UserDto.of(live.get(row.getBlockedId())), row.getCreatedAt()))
                .toList();
    }

    /** Whether either of the two has blocked the other. */
    public boolean blockedEitherWay(long one, long two) {
        return blocks.existsAcross(List.of(one), List.of(two));
    }

    /** Whether a block stands between anyone on one side and anyone on the other. */
    public boolean blockedAcross(Collection<Long> one, Collection<Long> two) {
        return blocks.existsAcross(one, two);
    }

    /** Which of {@code others} a block stands between {@code userId} and. */
    public Set<Long> blockedAmong(long userId, Collection<Long> others) {
        if (others.isEmpty()) return Set.of();
        return blocks.between(userId, others).stream()
                .map(block -> block.getBlockerId() == userId ? block.getBlockedId() : block.getBlockerId())
                .collect(Collectors.toSet());
    }
}
