package uz.wordbattle.common;

import java.util.stream.Collectors;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.context.request.ServletWebRequest;
import org.springframework.web.context.request.WebRequest;
import org.springframework.web.servlet.mvc.method.annotation.ResponseEntityExceptionHandler;

/**
 * Every response the API can fail with, in the one shape the app parses:
 * {@code {code, message, timestamp}}.
 *
 * <p>Extending {@link ResponseEntityExceptionHandler} is what makes a malformed
 * request answer as one. Spring raises its own family of exceptions before a
 * controller is ever reached — no such path, wrong method, a missing query
 * parameter, an id that is not a number, a body that is not JSON — and with only
 * the catch-all below, every one of them came back {@code 500 internal_error}. A
 * scripted sweep of bad requests against the live server found five in a minute
 * and none of them was a server fault. Two things went wrong each time: the app
 * reads 500 as "server broke, retry later" and its offline screen duly retried a
 * call that could never succeed, and each one logged a full stack trace at ERROR,
 * so a sweep filled the log in seconds and a real failure would have drowned in
 * it.
 *
 * <p>The base class is preferred over a handler per exception because the family
 * is longer than the five that showed up — media types, multipart size, path
 * variables, {@code ResponseStatusException} — and it grows between Spring
 * versions ({@code NoResourceFoundException} and
 * {@code HandlerMethodValidationException} both arrived in 6.1). It already maps
 * each member to the status the HTTP spec gives it, so nothing here has to track
 * that list; this class only decides what the body says and how loudly the
 * failure is logged.
 */
@RestControllerAdvice
public class GlobalExceptionHandler extends ResponseEntityExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    @ExceptionHandler(ApiException.class)
    public ResponseEntity<ApiError> handleApi(ApiException ex) {
        return ResponseEntity.status(ex.status()).body(ApiError.of(ex.code(), ex.getMessage()));
    }

    /**
     * Bean validation is the one framework failure worth quoting back: its field
     * errors name what to fix, and the app shows them. Overriding the base
     * class's hook rather than declaring a second {@code @ExceptionHandler} for
     * the same exception — two of those in one advice is a startup error.
     */
    @Override
    protected ResponseEntity<Object> handleMethodArgumentNotValid(
            MethodArgumentNotValidException ex, HttpHeaders headers, HttpStatusCode status, WebRequest request) {
        String message = ex.getBindingResult().getFieldErrors().stream()
                .map(e -> e.getField() + ": " + e.getDefaultMessage())
                .collect(Collectors.joining(", "));
        return handleExceptionInternal(ex, ApiError.of("validation_failed", message), headers, status, request);
    }

    /**
     * The funnel every one of the base class's handlers ends in, which is why
     * the body swap and the log level live here rather than in twenty overrides.
     *
     * <p>The status Spring chose decides both. A 4xx is the caller's mistake, so
     * it is one line and it is DEBUG: this is a public API, malformed requests
     * arrive on their own, and logging them by default is exactly how the log
     * filled up. Turn them on with
     * {@code logging.level.uz.wordbattle.common.GlobalExceptionHandler=DEBUG}
     * when chasing a client bug. A 5xx from this family is ours — a response
     * that could not be serialised, a path variable the mapping never declared —
     * and is indistinguishable from what the catch-all handles, so it keeps the
     * stack trace.
     */
    @Override
    protected ResponseEntity<Object> handleExceptionInternal(
            Exception ex, Object body, HttpHeaders headers, HttpStatusCode status, WebRequest request) {
        if (status.is5xxServerError()) {
            log.error("Unhandled exception", ex);
        } else if (log.isDebugEnabled()) {
            log.debug("{} -> {}: {}", describe(request), status.value(), ex.getMessage());
        }
        Object payload = body instanceof ApiError ? body : errorFor(status);
        return super.handleExceptionInternal(ex, payload, headers, status, request);
    }

    /**
     * Anything that reaches here is a bug rather than a bad request, so it stays
     * a 500 with the whole trace — that is how a real failure gets noticed, and
     * narrowing the family above was only ever about not being mistaken for one.
     */
    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiError> handleOther(Exception ex) {
        log.error("Unhandled exception", ex);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(ApiError.of("internal_error", "Kutilmagan xatolik"));
    }

    /**
     * A code and a message per status rather than per exception: the client can
     * act on the status, and the twenty-odd Spring exceptions behind a 400 all
     * mean the same thing to a player — the app sent something the server could
     * not read.
     */
    private static ApiError errorFor(HttpStatusCode status) {
        return switch (status.value()) {
            case 404 -> ApiError.of("not_found", "Bunday manzil yo'q");
            case 405 -> ApiError.of("method_not_allowed", "Bu usul qo'llab-quvvatlanmaydi");
            case 406 -> ApiError.of("not_acceptable", "So'ralgan javob formati yo'q");
            case 413 -> ApiError.of("payload_too_large", "So'rov hajmi juda katta");
            case 415 -> ApiError.of("unsupported_media_type", "So'rov formati qo'llab-quvvatlanmaydi");
            // Every other member of the family is a 400; the few 5xx ones say to
            // the client exactly what the catch-all says, and carry the same code
            // so the app cannot tell two kinds of server fault apart.
            default -> status.is5xxServerError()
                    ? ApiError.of("internal_error", "Kutilmagan xatolik")
                    : ApiError.of("bad_request", "So'rov noto'g'ri");
        };
    }

    /** Method and path, because a 405 is unreadable without both. */
    private static String describe(WebRequest request) {
        return request instanceof ServletWebRequest servlet
                ? servlet.getHttpMethod() + " " + servlet.getRequest().getRequestURI()
                : request.getDescription(false);
    }
}
