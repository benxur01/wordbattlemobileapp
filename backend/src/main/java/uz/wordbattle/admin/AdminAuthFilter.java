package uz.wordbattle.admin;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import org.springframework.lang.NonNull;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;
import uz.wordbattle.auth.AuthPrincipal;
import uz.wordbattle.user.UserRepository;

/**
 * Turns an authenticated player into an admin, for the {@code /api/admin/**}
 * routes and nowhere else.
 *
 * <p>{@code JwtAuthFilter} hands every valid token {@code ROLE_USER} and asks
 * the database one question to do it. Whether that player may also act on
 * everybody else's account is a second question with a second read, and it is
 * asked here rather than there because the answer matters on a handful of
 * routes and the token is checked on every request and every socket handshake
 * there is.
 *
 * <p>Hence the path test on the first line, which is not a micro-optimisation
 * but the whole design of this filter: a duel is a frame every few seconds from
 * both players, and the REST calls around it — the profile, the friend list, the
 * match history — are the ones a player waits on. None of them is an admin
 * route, and none of them pays for this.
 *
 * <p>The authentication is replaced rather than edited: the authorities on a
 * {@code UsernamePasswordAuthenticationToken} are immutable, which is the point
 * of them. Non-admins are left exactly as they were, and {@code SecurityConfig}
 * refuses them.
 */
@Component
public class AdminAuthFilter extends OncePerRequestFilter {

    /** The prefix {@code SecurityConfig} closes as {@code /api/admin/**}. */
    private static final String ADMIN_ROOT = "/api/admin";

    private static final GrantedAuthority ROLE_ADMIN = new SimpleGrantedAuthority("ROLE_ADMIN");

    private final UserRepository users;

    public AdminAuthFilter(UserRepository users) {
        this.users = users;
    }

    @Override
    protected void doFilterInternal(
            @NonNull HttpServletRequest request,
            @NonNull HttpServletResponse response,
            @NonNull FilterChain chain)
            throws ServletException, IOException {

        if (!isAdminPath(request.getRequestURI())) {
            chain.doFilter(request, response);
            return;
        }

        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication != null
                && authentication.getPrincipal() instanceof AuthPrincipal principal
                && users.isAdmin(principal.userId())) {
            List<GrantedAuthority> authorities = new ArrayList<>(authentication.getAuthorities());
            authorities.add(ROLE_ADMIN);
            SecurityContextHolder.getContext()
                    .setAuthentication(new UsernamePasswordAuthenticationToken(principal, null, authorities));
        }
        chain.doFilter(request, response);
    }

    /**
     * Exactly what {@code /api/admin/**} covers, and nothing either side of it.
     * A plain {@code startsWith(ADMIN_ROOT)} would also claim a future {@code
     * /api/administrators}; {@code startsWith("/api/admin/")} — which this used
     * to be — would leave {@code /api/admin} itself uncovered, and that one
     * <em>is</em> inside the rule, so an admin would have been refused their own
     * panel root. Neither costs anything today. Two spellings of the same
     * boundary do, because the day they drift the one that matters is the
     * looser.
     *
     * <p>Still a {@code startsWith} and one character on the hot path: every
     * request the game makes is answered by the first half of this.
     */
    private static boolean isAdminPath(String uri) {
        if (!uri.startsWith(ADMIN_ROOT)) return false;
        return uri.length() == ADMIN_ROOT.length() || uri.charAt(ADMIN_ROOT.length()) == '/';
    }
}
