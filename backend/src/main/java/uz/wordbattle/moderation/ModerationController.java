package uz.wordbattle.moderation;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Size;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import uz.wordbattle.auth.AuthPrincipal;
import uz.wordbattle.auth.CurrentUser;

/** Blocking and reporting another player, from wherever the app shows them. */
@RestController
@RequestMapping("/api/users")
public class ModerationController {

    private final BlockService blocks;
    private final ReportService reports;

    public ModerationController(BlockService blocks, ReportService reports) {
        this.blocks = blocks;
        this.reports = reports;
    }

    /**
     * {@code reason} is one of SPAM, ABUSE, CHEATING, INAPPROPRIATE_NAME,
     * OTHER; {@code context} one of chat, duel, profile; the rest is optional.
     * The two free-text fields are held to their column widths here, so an
     * oversized one is a 400 with a reason rather than a 500.
     */
    public record ReportRequest(
            String reason,
            @Size(max = UserReport.DETAILS_MAX, message = "Ko'pi bilan 500 ta belgi") String details,
            String context,
            @Size(max = 64, message = "Ko'pi bilan 64 ta belgi") String matchRef) {}

    public record ReportFiled(Long id) {}

    @PostMapping("/{id}/block")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void block(@CurrentUser AuthPrincipal principal, @PathVariable("id") Long id) {
        blocks.block(principal.userId(), id);
    }

    @DeleteMapping("/{id}/block")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void unblock(@CurrentUser AuthPrincipal principal, @PathVariable("id") Long id) {
        blocks.unblock(principal.userId(), id);
    }

    @GetMapping("/me/blocks")
    public List<BlockedUserDto> blocked(@CurrentUser AuthPrincipal principal) {
        return blocks.blockedBy(principal.userId());
    }

    @PostMapping("/{id}/report")
    @ResponseStatus(HttpStatus.CREATED)
    public ReportFiled report(
            @CurrentUser AuthPrincipal principal,
            @PathVariable("id") Long id,
            @Valid @RequestBody ReportRequest request) {
        UserReport filed = reports.file(
                principal.userId(), id, request.reason(), request.details(), request.context(), request.matchRef());
        return new ReportFiled(filed.getId());
    }
}
