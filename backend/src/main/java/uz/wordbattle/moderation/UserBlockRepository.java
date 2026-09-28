package uz.wordbattle.moderation;

import java.util.Collection;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface UserBlockRepository extends JpaRepository<UserBlock, UserBlock.Key> {

    List<UserBlock> findByBlockerIdOrderByCreatedAtDesc(Long blockerId);

    /**
     * Whether a block stands between anyone on one side and anyone on the
     * other, whichever of the two placed it. One player per side is the
     * ordinary question; two teams of two is the 2v2 queue's.
     */
    @Query("""
            select count(b) > 0 from UserBlock b
            where (b.blockerId in :one and b.blockedId in :two)
               or (b.blockerId in :two and b.blockedId in :one)
            """)
    boolean existsAcross(@Param("one") Collection<Long> one, @Param("two") Collection<Long> two);

    /** Every block between {@code userId} and any of {@code others}, in either direction. */
    @Query("""
            select b from UserBlock b
            where (b.blockerId = :userId and b.blockedId in :others)
               or (b.blockedId = :userId and b.blockerId in :others)
            """)
    List<UserBlock> between(@Param("userId") Long userId, @Param("others") Collection<Long> others);

    void deleteByBlockerIdOrBlockedId(Long blockerId, Long blockedId);
}
