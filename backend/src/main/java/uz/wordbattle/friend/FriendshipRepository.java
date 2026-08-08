package uz.wordbattle.friend;

import java.util.Collection;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface FriendshipRepository extends JpaRepository<Friendship, Long> {

    List<Friendship> findByUserId(Long userId);

    /** Every friendship edge leading out of any of these players, in one query. */
    List<Friendship> findByUserIdIn(Collection<Long> userIds);

    void deleteByUserId(Long userId);

    void deleteByFriendId(Long friendId);

    boolean existsByUserIdAndFriendId(Long userId, Long friendId);

    void deleteByUserIdAndFriendId(Long userId, Long friendId);
}
