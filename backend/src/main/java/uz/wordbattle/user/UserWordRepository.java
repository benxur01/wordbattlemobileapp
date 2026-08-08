package uz.wordbattle.user;

import java.util.Collection;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface UserWordRepository extends JpaRepository<UserWord, UserWord.Key> {

    @Query("select w.word from UserWord w where w.userId = :userId and w.word in :words")
    List<String> findKnown(@Param("userId") Long userId, @Param("words") Collection<String> words);

    long countByUserId(Long userId);

    void deleteByUserId(Long userId);
}
