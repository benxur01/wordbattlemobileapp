package uz.wordbattle.moderation;

import java.time.Instant;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import uz.wordbattle.moderation.UserReport.Status;

public interface UserReportRepository extends JpaRepository<UserReport, Long> {

    long countByReporterIdAndCreatedAtAfter(Long reporterId, Instant after);

    /** Newest first, by id for the same reason the audit log is — see {@code AdminAuditLogRepository}. */
    Page<UserReport> findByStatusOrderByIdDesc(Status status, Pageable pageable);

    /**
     * Closes the report, and only if it is still open, so a second admin — or
     * a second click — neither moves who resolved it and when, nor gets
     * another audit row out of it. Clears the persistence context for the
     * reason {@code UserRepository.ban} does: the report is read back straight
     * after.
     *
     * @return 1 when this call closed it, 0 when it already was.
     */
    @Modifying(clearAutomatically = true)
    @Query("""
            update UserReport r set r.status = :resolved, r.resolvedBy = :adminId, r.resolvedAt = :at
            where r.id = :id and r.status = :open
            """)
    int resolve(
            @Param("id") Long id,
            @Param("adminId") Long adminId,
            @Param("at") Instant at,
            @Param("open") Status open,
            @Param("resolved") Status resolved);
}
