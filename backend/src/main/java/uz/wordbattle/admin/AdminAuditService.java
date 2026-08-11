package uz.wordbattle.admin;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;

/**
 * Writes and reads the record of what admins have done.
 *
 * <p>{@link #record} declares no transaction of its own on purpose: it is meant
 * to run inside the caller's, so the log entry and the change it describes
 * commit together or not at all. A ban that survives while its audit row is
 * rolled back is worse than no log, because the log would then be believed.
 */
@Service
public class AdminAuditService {

    public static final String BAN = "user_ban";
    public static final String UNBAN = "user_unban";
    public static final String NICKNAME = "user_nickname";

    private final AdminAuditLogRepository entries;

    public AdminAuditService(AdminAuditLogRepository entries) {
        this.entries = entries;
    }

    /** @param detail free text, cut to what the column holds; may be null. */
    public void record(Long adminUserId, String action, Long targetUserId, String detail) {
        entries.save(new AdminAuditLog(adminUserId, action, targetUserId, trim(detail)));
    }

    public Page<AdminAuditLog> recent(Pageable pageable) {
        return entries.findAllByOrderByIdDesc(pageable);
    }

    private static String trim(String detail) {
        if (detail == null) return null;
        String value = detail.strip();
        if (value.isEmpty()) return null;
        return value.length() <= AdminAuditLog.DETAIL_MAX ? value : value.substring(0, AdminAuditLog.DETAIL_MAX);
    }
}
