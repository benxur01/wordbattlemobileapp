package uz.wordbattle.user;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import uz.wordbattle.auth.TokenGenerations;

public interface UserRepository extends JpaRepository<User, Long>, TokenGenerations {

    Optional<User> findByGoogleSubject(String googleSubject);

    /**
     * Answers the question every authenticated request asks: is the token in
     * front of us still the generation this account accepts?
     *
     * <p>A projection rather than the whole row — this runs on the way in to
     * every REST call and every socket handshake, and loading a player's rating
     * and statistics to compare one number would be a strange way to spend a
     * request.
     *
     * <p>Deleted accounts answer nothing at all, which is what stops a token
     * outliving the account it was issued for. The alternative — letting it
     * through and leaving each endpoint to notice the shell for itself — is
     * where the socket handshake used to let a deleted player back in.
     *
     * <p>Banned accounts answer nothing either, and for the same reason one
     * step on: a ban that only closed the REST door would leave the player's
     * socket — and with it the duel, the queue and the invites — running on the
     * token they already held, for as long as the token had left to live. Being
     * asked here means a ban is felt at both doors from the moment it commits,
     * without either of them knowing what a ban is.
     */
    @Override
    @Query("""
            select u.tokenGeneration from User u
            where u.id = :userId and u.deletedAt is null and u.bannedAt is null
            """)
    Optional<Long> currentFor(@Param("userId") Long userId);

    /**
     * Throws away every token the account holds. Straight at the column, like
     * {@link #touchLastSeen}: signing out is no reason to rewrite a player's
     * rating and statistics, and going through the entity would put this write
     * in a fight with a duel of theirs settling at the same moment.
     */
    @Modifying
    @Query("update User u set u.tokenGeneration = u.tokenGeneration + 1 where u.id = :userId")
    void revokeTokensOf(@Param("userId") Long userId);

    /**
     * Straight at the column rather than through the entity. A socket opening
     * or closing is no reason to rewrite a player's rating and statistics, and
     * doing so from a socket thread would undo a settlement committing
     * underneath it — or, now that the row is versioned, fail outright.
     */
    @Modifying
    @Query("update User u set u.lastSeenAt = :at where u.id = :id")
    void touchLastSeen(@Param("id") Long id, @Param("at") Instant at);

    @Query("select u from User u where lower(u.nickname) = lower(:nickname)")
    Optional<User> findByNicknameIgnoreCase(@Param("nickname") String nickname);

    @Query("select count(u) > 0 from User u where lower(u.nickname) = lower(:nickname)")
    boolean nicknameTaken(@Param("nickname") String nickname);

    /** {@code q} arrives already escaped for LIKE, with {@code !} as the escape. */
    @Query("""
            select u from User u
            where u.nickname is not null
              and lower(u.nickname) like lower(concat(:q, '%')) escape '!'
            order by u.rating desc
            """)
    List<User> searchByNicknamePrefix(@Param("q") String q, Pageable pageable);

    @Query("select u from User u where u.nickname is not null order by u.rating desc, u.id asc")
    List<User> topByRating(Pageable pageable);

    /**
     * The ladder a Global tournament picks its guest list off — see {@code
     * TournamentService#inviteTopRankedSolo}. {@link #topByRating} above is the
     * leaderboard's, and a banned account still sits on it until whoever reads
     * it says otherwise; this one cannot serve any, because {@code
     * TournamentService.startInternal} refuses to seed a banned player and
     * inviting one would only strand the bracket a seat short.
     */
    @Query("select u from User u where u.nickname is not null and u.bannedAt is null "
            + "order by u.rating desc, u.id asc")
    List<User> topEligibleByRating(Pageable pageable);

    /** 1-based position in the global ladder. */
    @Query("select count(u) + 1 from User u where u.nickname is not null and u.rating > :rating")
    long rankOf(@Param("rating") double rating);

    // ------------------------------------------------------------- admin panel
    //
    // The two updates below clear the persistence context behind them, which
    // neither revokeTokensOf nor touchLastSeen has to. An update written in JPQL
    // goes straight to the database and leaves whatever the session had already
    // loaded saying the opposite — and unlike those two, these are read back in
    // the same breath: the panel answers a ban with the account as it now
    // stands, which without this is the account as it stood a line earlier.
    // Whether the stale copy is still around depends on how long the session
    // lives, which is a Spring setting (open-in-view) and differs between the
    // server and the test suite. Not something a correctness question should
    // turn on.

    /**
     * Whether this account may use the admin panel. Asked once per {@code
     * /api/admin/**} request and never on any other path, so it costs the game
     * itself nothing.
     *
     * <p>A deleted or banned account is not an admin whatever its column says.
     * Neither can hold a usable token today — {@link #currentFor} refuses both —
     * but this is the check that decides who may act on everybody else's
     * account, and it should not be relying on another one to have run.
     */
    @Query("""
            select count(u) > 0 from User u
            where u.id = :userId and u.admin = true and u.deletedAt is null and u.bannedAt is null
            """)
    boolean isAdmin(@Param("userId") Long userId);

    /**
     * How many accounts can still open the panel — asked before a ban aimed at
     * an admin, and counting the same accounts {@link #isAdmin} would let in.
     *
     * <p>The role is granted from configuration on startup and by nothing in the
     * API, deliberately, so an admin panel with every admin banned out of it is
     * not a mistake anybody can undo from inside: it takes a redeploy with
     * {@code ADMIN_BOOTSTRAP_USER_ID} set to get back in.
     */
    @Query("""
            select count(u) from User u
            where u.admin = true and u.deletedAt is null and u.bannedAt is null
            """)
    long countActiveAdmins();

    /**
     * Straight at the column, like {@link #revokeTokensOf}: granting the role is
     * no reason to rewrite a player's rating and statistics, and going through
     * the entity would put this write in a fight with a duel of theirs settling
     * at the same moment.
     *
     * @return 1 when the role was granted, 0 when there is no such row or it
     *     already held it — which is what makes calling this on every start
     *     idempotent.
     */
    @Modifying
    @Query("update User u set u.admin = true where u.id = :userId and u.admin = false")
    int grantAdmin(@Param("userId") Long userId);

    /**
     * @return 1 when the account was banned by this call, 0 when it already was.
     *     The guard keeps a second ban from moving the timestamp, so the log
     *     goes on saying when the player actually lost the account.
     */
    @Modifying(clearAutomatically = true)
    @Query("update User u set u.bannedAt = :at where u.id = :userId and u.bannedAt is null")
    int ban(@Param("userId") Long userId, @Param("at") Instant at);

    /** @return 1 when the account was banned and is not any more, 0 otherwise. */
    @Modifying(clearAutomatically = true)
    @Query("update User u set u.bannedAt = null where u.id = :userId and u.bannedAt is not null")
    int unban(@Param("userId") Long userId);

    /**
     * The panel's search: a nickname, a display name, or an id typed straight
     * into the box. {@code pattern} arrives lowercased, wrapped in {@code %} and
     * escaped for LIKE with {@code !}, as {@link #searchByNicknamePrefix}
     * expects its own; {@code id} is the query parsed as a number, or a value no
     * row can hold when it is not one.
     *
     * <p>Unlike the player-facing search this one hides nothing — a deleted
     * shell and a banned account are exactly what an admin comes here to find.
     */
    @Query(value = """
            select u from User u
            where lower(coalesce(u.nickname, '')) like :pattern escape '!'
               or lower(coalesce(u.displayName, '')) like :pattern escape '!'
               or u.id = :id
            """,
            countQuery = """
            select count(u) from User u
            where lower(coalesce(u.nickname, '')) like :pattern escape '!'
               or lower(coalesce(u.displayName, '')) like :pattern escape '!'
               or u.id = :id
            """)
    Page<User> searchForAdmin(@Param("pattern") String pattern, @Param("id") Long id, Pageable pageable);

    /** Live accounts, for the dashboard. A deleted one is a shell, not a player. */
    @Query("select count(u) from User u where u.deletedAt is null")
    long countLive();

    @Query("select count(u) from User u where u.bannedAt is not null")
    long countBanned();
}
