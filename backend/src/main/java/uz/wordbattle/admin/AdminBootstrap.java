package uz.wordbattle.admin;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import uz.wordbattle.config.AppProperties;
import uz.wordbattle.user.UserRepository;

/**
 * Makes the first admin, which nothing else can.
 *
 * <p>The role is a column on {@code users} and the only thing that grants it is
 * the admin panel — which is closed to anyone who does not already hold it. That
 * circle has to be broken from outside the application, so one id comes in
 * through {@code wordbattle.admin.bootstrap-user-id} and is granted the role on
 * startup.
 *
 * <p>Deliberately the whole of it. This grants a role and never revokes one, and
 * it is not a list: a server is set up once, and everything after that belongs in
 * the panel where it leaves an audit trail. Running it on every start is safe
 * because the grant writes nothing to an account that already holds the role, so
 * the variable can be left exported and a restart is not an event.
 */
@Component
public class AdminBootstrap implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(AdminBootstrap.class);

    private final UserRepository users;
    private final AppProperties props;
    private final TransactionTemplate transactions;

    public AdminBootstrap(UserRepository users, AppProperties props, PlatformTransactionManager transactionManager) {
        this.users = users;
        this.props = props;
        this.transactions = new TransactionTemplate(transactionManager);
    }

    /**
     * Every way this can fail is a misconfiguration of an optional feature, so
     * every one of them is a log line rather than a server that will not start.
     * A duel in progress is worth more than an admin panel that is one restart
     * away from working.
     *
     * <p>The transaction is opened here rather than declared on the method: the
     * grant is an update written in JPQL and those need one, and a startup hook
     * is the worst place to be relying on an annotation having been proxied —
     * the only way to find out it was not would be a server that refuses to
     * start, on the one deploy where somebody has just set the variable.
     */
    @Override
    public void run(ApplicationArguments args) {
        if (!props.admin().configured()) return;

        String configured = props.admin().bootstrapUserId().trim();
        long userId;
        try {
            userId = Long.parseLong(configured);
        } catch (NumberFormatException e) {
            log.error("ADMIN_BOOTSTRAP_USER_ID '{}' raqam emas — hech kimga admin berilmadi", configured);
            return;
        }

        if (users.isAdmin(userId)) {
            log.info("Admin bootstrap: {} allaqachon admin", userId);
            return;
        }
        if (transactions.execute(status -> users.grantAdmin(userId)) == 1) {
            log.info("Admin bootstrap: {} adminga aylantirildi", userId);
        } else {
            log.warn("Admin bootstrap: {} bunday foydalanuvchi yo'q yoki o'chirilgan", userId);
        }
    }
}
