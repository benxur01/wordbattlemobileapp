package uz.wordbattle.auth;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import org.springframework.http.HttpStatus;
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
    public LoginResponse googleLogin(@Valid @RequestBody GoogleLoginRequest request) {
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

    /**
     * Signs the player out on the server, not only on the phone. Before this
     * existed "Chiqish" forgot the token locally and the server went on
     * honouring it for the rest of its 30-day life, so a copy of it — off an
     * old device backup, out of a proxy log, from a phone that changed hands —
     * still had the whole account.
     *
     * <p>It ends every session of the account rather than only the one that
     * called: the counter behind it belongs to the account. For a game people
     * play on one phone that is the safer reading of "sign me out" anyway, and
     * the alternative — remembering every token separately — is a stored row
     * per sign-in for a difference nobody here would notice.
     *
     * <p>Answers 204 even to a caller with no usable token, and says nothing
     * about which it was. The app calls this on its way out and signs out
     * locally whatever comes back; a 401 would only put an error in front of
     * somebody who is already leaving, and a token the server would not have
     * honoured has nothing to revoke.
     */
    @PostMapping("/logout")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void logout(@CurrentUser AuthPrincipal principal) {
        if (principal != null) {
            users.revokeTokens(principal.userId());
        }
    }

    private LoginResponse response(User user) {
        // A banned player is turned away here rather than handed a token that
        // authenticates nobody. The generation a token is measured against is
        // read only for a row that is neither deleted nor banned, so signing in
        // would otherwise succeed and every request after it fail with a 401 —
        // which the app answers by sending the player back to sign in again.
        if (user.isBanned()) {
            throw ApiException.forbidden("account_banned", "Akkaunt bloklangan");
        }
        // The generation comes off the row that was just read rather than being
        // looked up again: a token stamped with anything else would be refused
        // by the very next request, and the row in hand is the truth.
        return new LoginResponse(
                jwt.issue(user.getId(), user.getTokenGeneration()), UserDto.of(user), user.getNickname() == null);
    }
}
