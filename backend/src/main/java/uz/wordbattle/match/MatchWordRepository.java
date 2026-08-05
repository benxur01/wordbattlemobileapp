package uz.wordbattle.match;

import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface MatchWordRepository extends JpaRepository<MatchWord, Long> {
    List<MatchWord> findByMatchIdOrderByPositionAsc(Long matchId);
}
