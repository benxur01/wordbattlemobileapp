package uz.wordbattle.match;

import java.util.List;
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
}
