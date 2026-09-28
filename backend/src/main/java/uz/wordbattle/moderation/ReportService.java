package uz.wordbattle.moderation;

import java.time.Duration;
import java.time.Instant;
import java.util.Locale;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import uz.wordbattle.admin.AdminAuditService;
import uz.wordbattle.common.ApiException;
import uz.wordbattle.moderation.UserReport.Status;
import uz.wordbattle.user.UserService;

/**
 * Players reporting one another, and the admin panel working through what
 * they reported.
 */
@Service
public class ReportService {

    private static final Logger log = LoggerFactory.getLogger(ReportService.class);

    /**
     * How many reports one player may file in a day. Far more than anybody
     * reporting what was done to them needs, and few enough that nobody can
     * bury the panel's queue under a rival's name.
     */
    static final int MAX_REPORTS_PER_DAY = 10;

    private final UserReportRepository reports;
    private final UserService users;
    private final AdminAuditService audit;

    public ReportService(UserReportRepository reports, UserService users, AdminAuditService audit) {
        this.reports = reports;
        this.users = users;
        this.audit = audit;
    }

    /**
     * Files a report. {@code reason} is one of {@link UserReport.Reason} and
     * {@code context}, when there is one, one of {@link UserReport.Context},
     * either in any case; {@code details} and {@code matchRef} arrive already
     * held to their column widths by the controller.
     */
    @Transactional
    public UserReport file(
            Long reporterId, Long reportedId, String reason, String details, String context, String matchRef) {
        if (reporterId.equals(reportedId)) {
            throw ApiException.badRequest("self_report", "O'zingiz haqingizda shikoyat qila olmaysiz");
        }
        UserReport.Reason parsedReason = parse(UserReport.Reason.class, reason);
        if (parsedReason == null) {
            throw ApiException.badRequest("invalid_reason", "Shikoyat sababini tanlang");
        }
        UserReport.Context parsedContext = null;
        if (context != null && !context.isBlank()) {
            parsedContext = parse(UserReport.Context.class, context);
            if (parsedContext == null) {
                throw ApiException.badRequest("invalid_context", "Shikoyat joyi noto'g'ri");
            }
        }
        users.require(reportedId);
        // A count, not a lock: two reports landing in the same instant at the
        // limit can both get through, which costs the queue one report.
        if (reports.countByReporterIdAndCreatedAtAfter(reporterId, Instant.now().minus(Duration.ofDays(1)))
                >= MAX_REPORTS_PER_DAY) {
            throw new ApiException(
                    HttpStatus.TOO_MANY_REQUESTS,
                    "report_limit",
                    "Bugun juda ko'p shikoyat yubordingiz — ertaga qayta urinib ko'ring");
        }
        return reports.save(new UserReport(
                reporterId, reportedId, parsedReason, blankToNull(details), parsedContext, blankToNull(matchRef)));
    }

    /** One page of the reports in {@code status} — {@code open} or {@code resolved}, in any case. */
    public Page<UserReport> list(String status, Pageable pageable) {
        Status parsed = parse(Status.class, status);
        if (parsed == null) {
            throw ApiException.badRequest("invalid_status", "Holat noto'g'ri: open yoki resolved");
        }
        return reports.findByStatusOrderByIdDesc(parsed, pageable);
    }

    /**
     * Closes a report, with an audit row in the same transaction — the way
     * every change the panel makes is recorded. Closing one already closed
     * changes nothing and records nothing.
     */
    @Transactional
    public UserReport resolve(Long adminId, Long reportId) {
        UserReport report = require(reportId);
        if (reports.resolve(reportId, adminId, Instant.now(), Status.OPEN, Status.RESOLVED) == 1) {
            audit.record(
                    adminId,
                    AdminAuditService.REPORT_RESOLVE,
                    report.getReportedId(),
                    "#" + reportId + " · " + report.getReason().name().toLowerCase(Locale.ROOT));
            log.info("Admin {} resolved report {}", adminId, reportId);
        }
        return require(reportId);
    }

    private UserReport require(Long reportId) {
        return reports.findById(reportId)
                .orElseThrow(() -> ApiException.notFound("report_not_found", "Shikoyat topilmadi"));
    }

    private static <E extends Enum<E>> E parse(Class<E> type, String raw) {
        if (raw == null) return null;
        try {
            return Enum.valueOf(type, raw.strip().toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException e) {
            return null;
        }
    }

    private static String blankToNull(String value) {
        if (value == null) return null;
        String stripped = value.strip();
        return stripped.isEmpty() ? null : stripped;
    }
}
