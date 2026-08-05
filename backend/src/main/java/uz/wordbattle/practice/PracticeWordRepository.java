package uz.wordbattle.practice;

import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface PracticeWordRepository extends JpaRepository<PracticeWord, Long> {
    List<PracticeWord> findAllByOrderByIdAsc();
}
