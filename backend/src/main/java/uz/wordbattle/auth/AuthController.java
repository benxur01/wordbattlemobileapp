package uz.wordbattle.auth;

import jakarta.validation.constraints.NotBlank;
import org.springframework.web.bind.annotation.*;
import uz.wordbattle.common.ApiException;
import uz.wordbattle.config.AppProperties;
import uz.wordbattle.user.User;
import uz.wordbattle.user.UserDto;
import uz.wordbattle.user.UserService;

@RestController
@RequestMapping("/api/auth")
public class AuthController {

    private final GoogleAuthService google;
    private final JwtService jwt;
    private final UserService users;
    private final AppProperties props;

    public AuthController(GoogleAuthService google, JwtService jwt, UserService users, AppProperties props) {
        this.google = google;
        this.jwt = jwt;
        this.users = users;
        this.props = props;
    }

    public record GoogleLoginRequest(@NotBlank String idToken) {}

    public record DevLoginRequest(String displayName) {}

    public record LoginResponse(String token, UserDto user, boolean needsNickname) {}

    /**
     * The only production login: the client forwards the idToken Google
     * Sign-In gave it, and the server checks it against Google's public keys.
     */
    @PostMapping("/google")
    public LoginResponse googleLogin(@RequestBody GoogleLoginRequest request) {
        GoogleAuthService.GoogleUser googleUser = google.verify(request.idToken());
        User user = users.findOrCreateByGoogleSubject(googleUser.subject(), googleUser.displayName());
        return response(user);
    }

    /**
     * Development shortcut so the app and the tests can be exercised without
     * Google credentials. Every call mints a fresh throwaway account — it
     * carries no provider identity, so it can never be handed to a real player
     * signing in with Google. Disabled unless
     * {@code wordbattle.dev-login-enabled} is true.
     */
    @PostMapping("/dev")
    public LoginResponse devLogin(@RequestBody DevLoginRequest request) {
        if (!props.devLoginEnabled()) {
            throw ApiException.unauthorized("dev_login_disabled", "Dev login o'chirilgan");
        }
        String name = request.displayName() != null && !request.displayName().isBlank()
                ? request.displayName()
                : "dev_" + System.nanoTime() % 1_000_000_000L;
        return response(users.createDevUser(name));
    }

    private LoginResponse response(User user) {
        return new LoginResponse(jwt.issue(user.getId()), UserDto.of(user), user.getNickname() == null);
    }
}
