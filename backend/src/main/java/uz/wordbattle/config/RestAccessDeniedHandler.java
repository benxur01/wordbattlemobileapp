package uz.wordbattle.config;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.web.access.AccessDeniedHandler;
import org.springframework.stereotype.Component;
import uz.wordbattle.common.ApiError;

/**
 * The 403 half of what {@link uz.wordbattle.auth.RestAuthEntryPoint} does for
 * 401: a refusal in the one shape every other failure in this API arrives in,
 * {@code {code, message, timestamp}}.
 *
 * <p>Without it Spring writes its own error body — an HTML page, or Boot's
 * {@code /error} JSON, depending on what is on the classpath — and a client that
 * parses one shape for every response has to grow a second path for the one case
 * it is least likely to be tested against.
 */
@Component
public class RestAccessDeniedHandler implements AccessDeniedHandler {

    private final ObjectMapper mapper;

    public RestAccessDeniedHandler(ObjectMapper mapper) {
        this.mapper = mapper;
    }

    @Override
    public void handle(HttpServletRequest request, HttpServletResponse response, AccessDeniedException denied)
            throws IOException {
        response.setStatus(HttpStatus.FORBIDDEN.value());
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        mapper.writeValue(response.getOutputStream(), ApiError.of("forbidden", "Ruxsat yo'q"));
    }
}
