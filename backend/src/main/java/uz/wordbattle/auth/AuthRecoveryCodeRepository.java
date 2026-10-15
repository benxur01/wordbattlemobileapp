package uz.wordbattle.auth;

import jakarta.persistence.LockModeType;
import java.time.Instant;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface AuthRecoveryCodeRepository extends JpaRepository<AuthRecoveryCode, Long> {

    Optional<AuthRecoveryCode> findByUserIdAndPurpose(Long userId, String purpose);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select c from AuthRecoveryCode c where c.userId = :userId and c.purpose = :purpose")
    Optional<AuthRecoveryCode> lockByUserAndPurpose(@Param("userId") Long userId, @Param("purpose") String purpose);

    void deleteByUserIdAndPurpose(Long userId, String purpose);

    void deleteByUserId(Long userId);

    long deleteByExpiresAtBefore(Instant expiresAt);
}
