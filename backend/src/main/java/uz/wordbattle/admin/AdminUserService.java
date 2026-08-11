package uz.wordbattle.admin;

import java.time.Instant;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import uz.wordbattle.common.ApiException;
import uz.wordbattle.user.AccountDeletionService;
import uz.wordbattle.user.User;
import uz.wordbattle.user.UserRepository;
import uz.wordbattle.user.UserService;

/**
 * What an admin can do to somebody else's account: find it, take it away, give
 * it back, and rename it.
 *
 * <p>Every one of those writes an audit row in the same transaction as the
 * change — see {@link AdminAuditService} — so the panel cannot make a change
 * that leaves no trace of who made it.
 */
@Service
public class AdminUserService {

    private static final Logger log = LoggerFactory.getLogger(AdminUserService.class);

    private final UserRepository users;
    private final UserService userService;
    private final AdminAuditService audit;
    private final AccountDeletionService.SessionEnder sessionEnder;
    private final TransactionTemplate transactions;

    public AdminUserService(
            UserRepository users,
            UserService userService,
            AdminAuditService audit,
            AccountDeletionService.SessionEnder sessionEnder,
            PlatformTransactionManager transactionManager) {
        this.users = users;
        this.userService = userService;
        this.audit = audit;
        this.sessionEnder = sessionEnder;
        this.transactions = new TransactionTemplate(transactionManager);
    }

    /**
     * The panel's user list. An empty query is the whole table, newest account
     * first; anything else is matched against nickname, display name and id.
     *
     * <p>Deleted shells and banned accounts are included, unlike everywhere else
     * in this server: they are what an admin comes to this screen looking for.
     */
    public Page<User> search(String query, Pageable pageable) {
        String q = query == null ? "" : query.strip();
        if (q.isEmpty()) return users.findAll(pageable);
        // `%` and `_` are LIKE wildcards, escaped here as UserService.search
        // escapes them — unescaped, a search for "%" matched every player there
        // is, which on this screen is every account on the server.
        String pattern = "%" + q.toLowerCase().replace("!", "!!").replace("%", "!%").replace("_", "!_") + "%";
        return users.searchForAdmin(pattern, asId(q), pageable);
    }

    /**
     * A single account, deleted shells included — an admin looking into a
     * complaint about an account that has since been erased still has to be able
     * to read the row an old match points at.
     */
    public User require(Long id) {
        if (id == null) throw ApiException.notFound("user_not_found", "Foydalanuvchi topilmadi");
        return users.findById(id)
                .orElseThrow(() -> ApiException.notFound("user_not_found", "Foydalanuvchi topilmadi"));
    }

    /**
     * Takes the account away from the player. Idempotent: banning an account
     * that is already banned changes nothing, writes no audit row, and does not
     * move the timestamp that records when they actually lost it.
     *
     * <p>The session is ended before the row is written and outside the
     * transaction, exactly as {@code AccountDeletionService} does it and for the
     * same two reasons. Every way into a duel goes through the socket registry,
     * so closing the socket first is what stops a duel starting in the gap; and
     * the wait for a duel of theirs to settle is a wait on another thread
     * writing this very row, which inside a transaction holding it would be a
     * deadlock that resolves itself only by timing out.
     */
    public User ban(Long adminId, Long targetId, String reason) {
        User target = require(targetId);
        if (target.isBanned()) return target;

        sessionEnder.endSessionOf(targetId);

        transactions.executeWithoutResult(status -> {
            // A second ban that landed while the session was being torn down
            // has already done all of this.
            if (users.ban(targetId, Instant.now()) == 0) return;
            // Belt and braces beside the ban itself. A banned account has no
            // current token generation, so its tokens are already refused — but
            // this is what keeps them refused after an unban, rather than
            // handing the account back with every token it ever held.
            users.revokeTokensOf(targetId);
            audit.record(adminId, AdminAuditService.BAN, targetId, reason);
            log.info("Admin {} banned account {}", adminId, targetId);
        });
        return require(targetId);
    }

    /** Idempotent in the same way: an account that is not banned is left alone. */
    public User unban(Long adminId, Long targetId) {
        require(targetId);
        transactions.executeWithoutResult(status -> {
            if (users.unban(targetId) == 0) return;
            audit.record(adminId, AdminAuditService.UNBAN, targetId, null);
            log.info("Admin {} unbanned account {}", adminId, targetId);
        });
        return require(targetId);
    }

    /**
     * Renames a player, for the nickname nobody should have to keep.
     *
     * <p>Straight through {@code UserService.claimNickname}, so the panel is held
     * to the rules the onboarding screen is: the same character policy, the same
     * reserved names, and the same unique index deciding who gets a name two
     * people asked for at once. An admin who could set a nickname the game
     * itself refuses would be creating rows nothing else can handle.
     */
    public User rename(Long adminId, Long targetId, String nickname) {
        return transactions.execute(status -> {
            String previous = require(targetId).getNickname();
            User renamed = userService.claimNickname(targetId, nickname);
            audit.record(
                    adminId,
                    AdminAuditService.NICKNAME,
                    targetId,
                    (previous == null ? "—" : previous) + " → " + renamed.getNickname());
            log.info("Admin {} renamed account {} to {}", adminId, targetId, renamed.getNickname());
            return renamed;
        });
    }

    /** The query as an id when it is one, and an id no row can hold when it is not. */
    private static Long asId(String query) {
        try {
            return Long.valueOf(query);
        } catch (NumberFormatException e) {
            return -1L;
        }
    }
}
