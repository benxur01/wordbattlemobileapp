package uz.wordbattle.auth;

import java.security.Principal;

/** The authenticated player id, available to controllers and WebSocket sessions. */
public record AuthPrincipal(Long userId) implements Principal {
    @Override
    public String getName() {
        return String.valueOf(userId);
    }
}
