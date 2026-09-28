package uz.wordbattle.moderation;

import jakarta.persistence.*;
import java.time.Instant;

/**
 * One player's complaint about another, and — once an admin has dealt with
 * it — who closed it and when.
 */
@Entity
@Table(name = "user_reports")
public class UserReport {

    /** The most of the reporter's own words a report keeps. */
    public static final int DETAILS_MAX = 500;

    public enum Reason { SPAM, ABUSE, CHEATING, INAPPROPRIATE_NAME, OTHER }

    /** Where in the app the report was filed from. */
    public enum Context { CHAT, DUEL, PROFILE }

    public enum Status { OPEN, RESOLVED }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "reporter_id", nullable = false)
    private Long reporterId;

    @Column(name = "reported_id", nullable = false)
    private Long reportedId;

    @Enumerated(EnumType.STRING)
    @Column(name = "reason", nullable = false, length = 32)
    private Reason reason;

    @Column(name = "details", length = DETAILS_MAX)
    private String details;

    @Enumerated(EnumType.STRING)
    @Column(name = "context", length = 16)
    private Context context;

    /** The live duel the report was filed during, as the app knows it. */
    @Column(name = "match_ref", length = 64)
    private String matchRef;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private Status status = Status.OPEN;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt = Instant.now();

    @Column(name = "resolved_by")
    private Long resolvedBy;

    @Column(name = "resolved_at")
    private Instant resolvedAt;

    protected UserReport() {}

    public UserReport(
            Long reporterId, Long reportedId, Reason reason, String details, Context context, String matchRef) {
        this.reporterId = reporterId;
        this.reportedId = reportedId;
        this.reason = reason;
        this.details = details;
        this.context = context;
        this.matchRef = matchRef;
    }

    public Long getId() { return id; }
    public Long getReporterId() { return reporterId; }
    public Long getReportedId() { return reportedId; }
    public Reason getReason() { return reason; }
    public String getDetails() { return details; }
    public Context getContext() { return context; }
    public String getMatchRef() { return matchRef; }
    public Status getStatus() { return status; }
    public Instant getCreatedAt() { return createdAt; }
    public Long getResolvedBy() { return resolvedBy; }
    public Instant getResolvedAt() { return resolvedAt; }
}
