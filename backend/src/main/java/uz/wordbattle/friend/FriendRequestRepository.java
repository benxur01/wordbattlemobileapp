package uz.wordbattle.friend;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import uz.wordbattle.friend.FriendRequestEntity.Status;

public interface FriendRequestRepository extends JpaRepository<FriendRequestEntity, Long> {

    List<FriendRequestEntity> findByToUserIdAndStatus(Long toUserId, Status status);

    Optional<FriendRequestEntity> findByFromUserIdAndToUserIdAndStatus(Long fromUserId, Long toUserId, Status status);

    long countByToUserIdAndStatus(Long toUserId, Status status);

    void deleteByFromUserIdOrToUserId(Long fromUserId, Long toUserId);
}
