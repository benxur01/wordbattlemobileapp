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

    private final TelegramAuthService telegram;
    private final JwtService jwt;
    private final UserService users;
    private final AppProperties props;

    public AuthController(TelegramAuthService telegram, JwtService jwt, UserService users, AppProperties props) {
        this.telegram = telegram;
        this.jwt = jwt;
        this.users = users;
        this.props = props;
    }

    public record TelegramLoginRequest(@NotBlank String initData) {}

    public record DevLoginRequest(Long telegramId, String displayName) {}

    public record LoginResponse(String token, UserDto user, boolean needsNickname) {}

    /** Production login: the client forwards Telegram's signed initData. */
    @PostMapping("/telegram")
    public LoginResponse telegramLogin(@RequestBody TelegramLoginRequest request) {
        TelegramAuthService.TelegramUser tgUser = telegram.verify(request.initData());
        User user = users.findOrCreateByTelegramId(tgUser.id(), tgUser.displayName());
        return response(user);
    }

    /**
     * Development shortcut so the app can be exercised without a bot token.
     * Disabled unless {@code wordbattle.dev-login-enabled} is true.
     */
    @PostMapping("/dev")
    public LoginResponse devLogin(@RequestBody DevLoginRequest request) {
        if (!props.devLoginEnabled()) {
            throw ApiException.unauthorized("dev_login_disabled", "Dev login o'chirilgan");
        }
        long telegramId = request.telegramId() != null ? request.telegramId() : System.nanoTime() % 1_000_000_000L;
        String name = request.displayName() != null ? request.displayName() : "dev_" + telegramId;
        return response(users.findOrCreateByTelegramId(telegramId, name));
    }

    private LoginResponse response(User user) {
        return new LoginResponse(jwt.issue(user.getId()), UserDto.of(user), user.getNickname() == null);
    }
}
