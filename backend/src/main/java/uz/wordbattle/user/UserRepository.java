package uz.wordbattle.user;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
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
     */
    @Override
    @Query("select u.tokenGeneration from User u where u.id = :userId and u.deletedAt is null")
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

    /** 1-based position in the global ladder. */
    @Query("select count(u) + 1 from User u where u.nickname is not null and u.rating > :rating")
    long rankOf(@Param("rating") double rating);
}
