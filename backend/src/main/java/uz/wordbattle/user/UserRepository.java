package uz.wordbattle.user;

import java.util.List;
import java.util.Optional;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface UserRepository extends JpaRepository<User, Long> {

    Optional<User> findByGoogleSubject(String googleSubject);

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
