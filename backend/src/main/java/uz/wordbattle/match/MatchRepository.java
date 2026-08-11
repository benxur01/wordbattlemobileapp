package uz.wordbattle.match;

import java.time.Instant;
import java.util.List;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface MatchRepository extends JpaRepository<MatchEntity, Long> {

    @Query("""
            select m from MatchEntity m
            where m.playerOneId = :userId or m.playerTwoId = :userId
            order by m.finishedAt desc
            """)
    List<MatchEntity> findHistory(@Param("userId") Long userId, Pageable pageable);

    // ------------------------------------------------------------- admin panel

    /**
     * Every duel on the server, newest first. Bound to no account, unlike
     * {@link #findHistory} above — which is the whole difference, and the reason
     * it is a query of its own rather than that one with the filter relaxed.
     */
    @Query(value = "select m from MatchEntity m order by m.finishedAt desc",
            countQuery = "select count(m) from MatchEntity m")
    Page<MatchEntity> findAllForAdmin(Pageable pageable);

    @Query("select count(m) from MatchEntity m where m.finishedAt >= :since")
    long countFinishedSince(@Param("since") Instant since);

    long countByBotOpponentTrue();
}
