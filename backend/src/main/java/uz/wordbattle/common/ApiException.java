package uz.wordbattle.common;

import org.springframework.http.HttpStatus;

/** Carries an HTTP status plus a stable machine-readable code for the client. */
public class ApiException extends RuntimeException {

    private final HttpStatus status;
    private final String code;

    public ApiException(HttpStatus status, String code, String message) {
        super(message);
        this.status = status;
        this.code = code;
    }

    public static ApiException notFound(String code, String message) {
        return new ApiException(HttpStatus.NOT_FOUND, code, message);
    }

    public static ApiException badRequest(String code, String message) {
        return new ApiException(HttpStatus.BAD_REQUEST, code, message);
    }

    public static ApiException conflict(String code, String message) {
        return new ApiException(HttpStatus.CONFLICT, code, message);
    }

    public static ApiException unauthorized(String code, String message) {
        return new ApiException(HttpStatus.UNAUTHORIZED, code, message);
    }

    /**
     * The token is good and the account behind it is real — it just may not do
     * this. Distinct from {@link #unauthorized} on purpose: the app sends a 401
     * back to onboarding, and doing that to a banned player would put them on a
     * sign-in loop that ends where it started.
     */
    public static ApiException forbidden(String code, String message) {
        return new ApiException(HttpStatus.FORBIDDEN, code, message);
    }

    public HttpStatus status() {
        return status;
    }

    public String code() {
        return code;
    }
}
