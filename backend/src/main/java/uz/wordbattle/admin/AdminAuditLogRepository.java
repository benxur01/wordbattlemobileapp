package uz.wordbattle.admin;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

public interface AdminAuditLogRepository extends JpaRepository<AdminAuditLog, Long> {

    /**
     * Newest first, by id rather than by {@code createdAt}: two actions inside
     * the same millisecond would otherwise come back in an order that changes
     * between reads, and the id is the order they were written in.
     */
    Page<AdminAuditLog> findAllByOrderByIdDesc(Pageable pageable);
}
