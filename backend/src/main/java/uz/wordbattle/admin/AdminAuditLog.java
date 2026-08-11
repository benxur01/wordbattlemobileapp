package uz.wordbattle.admin;

import jakarta.persistence.*;
import java.time.Instant;

/**
 * One line of the admin panel's paper trail: who did what, to whom, and when.
 *
 * <p>Write-once. There is no setter on it and no endpoint that edits or deletes
 * one, which is the only property that makes a log of this kind worth reading —
 * an admin who can rewrite the record of what they did leaves no record at all.
 */
@Entity
@Table(name = "admin_audit_log")
public class AdminAuditLog {

    /**
     * As much of the free-text detail as the column keeps. Longer values are cut
     * rather than refused: a detail that fails to save would take the change it
     * describes down with it, and the change is the more important half.
     */
    public static final int DETAIL_MAX = 512;

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "admin_user_id", nullable = false)
    private Long adminUserId;

    /** One of the constants on {@link AdminAuditService}. */
    @Column(name = "action", nullable = false, length = 64)
    private String action;

    /** Null for an action that is about no single player. */
    @Column(name = "target_user_id")
    private Long targetUserId;

    /** Whatever the action is worth knowing beyond its name — a reason, a rename. */
    @Column(name = "detail", length = DETAIL_MAX)
    private String detail;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt = Instant.now();

    protected AdminAuditLog() {}

    public AdminAuditLog(Long adminUserId, String action, Long targetUserId, String detail) {
        this.adminUserId = adminUserId;
        this.action = action;
        this.targetUserId = targetUserId;
        this.detail = detail;
    }

    public Long getId() { return id; }
    public Long getAdminUserId() { return adminUserId; }
    public String getAction() { return action; }
    public Long getTargetUserId() { return targetUserId; }
    public String getDetail() { return detail; }
    public Instant getCreatedAt() { return createdAt; }
}
