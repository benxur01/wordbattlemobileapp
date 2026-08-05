package uz.wordbattle.rating;

import java.time.Instant;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface RatingHistoryRepository extends JpaRepository<RatingHistory, Long> {

    List<RatingHistory> findByUserIdAndRecordedAtAfterOrderByRecordedAtAsc(Long userId, Instant after);
}
