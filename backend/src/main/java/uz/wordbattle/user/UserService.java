package uz.wordbattle.user;

import java.time.Instant;
import java.time.LocalDate;
import java.util.Collection;
import java.util.List;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.domain.PageRequest;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import uz.wordbattle.common.ApiException;
import uz.wordbattle.config.AppProperties;

@Service
public class UserService {

    private static final int MIN_PASSWORD_LENGTH = 6;

    private final UserRepository users;
    private final AppProperties props;
    private final PasswordEncoder passwordEncoder;

    public UserService(UserRepository users, AppProperties props, PasswordEncoder passwordEncoder) {
        this.users = users;
        this.props = props;
        this.passwordEncoder = passwordEncoder;
    }

    @Transactional
    public User findOrCreateByGoogleSubject(String googleSubject, String displayName) {
        return users.findByGoogleSubject(googleSubject)
                .map(this::seen)
                .orElseGet(() -> users.save(User.withGoogle(googleSubject, displayName)));
    }

    private User seen(User user) {
        user.setLastSeenAt(Instant.now());
        return user;
    }

    /** Backs {@code /api/auth/dev}: a fresh account with no provider behind it. */
    @Transactional
    public User createDevUser(String displayName) {
        return users.save(User.withoutProvider(displayName));
    }

    /**
     * A live player. A deleted account is gone as far as everything the game
     * does is concerned — including the token it left behind, which stops
     * working here rather than resolving to an empty shell.
     */
    public User require(Long id) {
        if (id == null) throw ApiException.notFound("user_not_found", "Foydalanuvchi topilmadi");
        return users.findById(id)
                .filter(user -> !user.isDeleted())
                .orElseThrow(() -> ApiException.notFound("user_not_found", "Foydalanuvchi topilmadi"));
    }

    /**
     * Bulk lookup for the callers that would otherwise loop over {@link #require}
     * — and, like it, live players only. A deleted account keeps its row, so
     * without this filter it came back as a nameless shell that every caller had
     * to recognise for itself; missing is the one state they all already handle.
     */
    public List<User> allByIds(Collection<Long> ids) {
        return ids.isEmpty()
                ? List.of()
                : users.findAllById(ids).stream().filter(user -> !user.isDeleted()).toList();
    }

    public boolean nicknameTaken(String nickname) {
        return users.nicknameTaken(NicknamePolicy.normalise(nickname));
    }

    public List<String> suggestions(String nickname) {
        return NicknamePolicy.suggestions(nickname, this::nicknameTaken);
    }

    /**
     * The format check every path that assigns a nickname shares — claiming
     * one on the second onboarding screen and choosing one at password
     * registration fail on the same rules with the same message.
     */
    private String validatedNickname(String rawNickname) {
        NicknamePolicy.Result result = NicknamePolicy.validate(rawNickname);
        if (result != NicknamePolicy.Result.OK) {
            throw ApiException.badRequest("nickname_invalid", NicknamePolicy.messageFor(result));
        }
        return NicknamePolicy.normalise(rawNickname);
    }

    /**
     * Claims a nickname for the player. The unique index is the real arbiter —
     * two players sending the same name at the same moment both pass the
     * "is it free" check, and the loser gets a conflict here.
     */
    @Transactional
    public User claimNickname(Long userId, String rawNickname) {
        String nickname = validatedNickname(rawNickname);
        if (users.nicknameTaken(nickname)) {
            throw ApiException.conflict("nickname_taken", "Bu taxallus band");
        }
        User user = require(userId);
        user.setNickname(nickname);
        try {
            return users.saveAndFlush(user);
        } catch (DataIntegrityViolationException e) {
            throw ApiException.conflict("nickname_taken", "Bu taxallus band");
        }
    }

    /**
     * Instagram-style sign-up: the nickname doubles as the login name, chosen
     * and claimed in the same step instead of over two onboarding screens the
     * way Google accounts do it. The unique index is still the real arbiter,
     * same as {@link #claimNickname} — a name taken between the check above
     * and the insert lands here as the same conflict.
     */
    @Transactional
    public User registerWithPassword(String rawNickname, String rawPassword) {
        String nickname = validatedNickname(rawNickname);
        if (rawPassword == null || rawPassword.length() < MIN_PASSWORD_LENGTH) {
            throw ApiException.badRequest("password_too_short", "Parol kamida 6 ta belgidan iborat bo'lishi kerak");
        }
        if (users.nicknameTaken(nickname)) {
            throw ApiException.conflict("nickname_taken", "Bu taxallus band");
        }
        String hash = passwordEncoder.encode(rawPassword);
        try {
            return users.saveAndFlush(User.withPassword(nickname, hash));
        } catch (DataIntegrityViolationException e) {
            throw ApiException.conflict("nickname_taken", "Bu taxallus band");
        }
    }

    /**
     * The password counterpart to {@link #findOrCreateByGoogleSubject}: looks
     * the nickname up and checks the password against it in one generic
     * failure. "No such nickname" and "wrong password" answer identically —
     * telling them apart would let a caller learn which nicknames exist
     * without ever guessing a password.
     */
    @Transactional
    public User authenticateWithPassword(String rawNickname, String rawPassword) {
        User user = users.findByNicknameIgnoreCase(NicknamePolicy.normalise(rawNickname)).orElse(null);
        if (user == null || user.getPasswordHash() == null || !passwordEncoder.matches(rawPassword, user.getPasswordHash())) {
            throw ApiException.unauthorized("invalid_credentials", "Login yoki parol xato");
        }
        return seen(user);
    }

    @Transactional
    public User updateCity(Long userId, String city) {
        User user = require(userId);
        user.setCity(city == null || city.isBlank() ? null : city.trim());
        return user;
    }

    public List<User> search(String query, Long excludeUserId, int limit) {
        String q = NicknamePolicy.normalise(query);
        if (q.isEmpty()) return List.of();
        // `%` and `_` are LIKE wildcards: unescaped, a search for "%" matched
        // every player on the server.
        String pattern = q.replace("!", "!!").replace("%", "!%").replace("_", "!_");
        return users.searchByNicknamePrefix(pattern, PageRequest.of(0, Math.max(1, Math.min(limit, 50)))).stream()
                .filter(u -> !u.getId().equals(excludeUserId))
                .toList();
    }

    public long rankOf(User user) {
        return users.rankOf(user.getRating());
    }

    /**
     * Daily streak bookkeeping: playing again the next calendar day extends it,
     * a gap resets it to one. Called once per finished match.
     *
     * <p>"Day" means a local calendar day. Counting in UTC would end a player's
     * streak at 05:00 their time, which is neither what the screen promises nor
     * what anyone would expect.
     */
    @Transactional
    public void touchStreak(User user, Instant playedAt) {
        LocalDate today = playedAt.atZone(props.timeZone()).toLocalDate();
        LocalDate last = user.getLastPlayedOn();
        if (last == null || last.isBefore(today.minusDays(1))) {
            user.setStreakDays(1);
        } else if (last.equals(today.minusDays(1))) {
            user.setStreakDays(user.getStreakDays() + 1);
        }
        user.setLastPlayedOn(today);
    }

    @Transactional
    public void markSeen(Long userId) {
        users.touchLastSeen(userId, Instant.now());
    }

    /**
     * Signs the account out everywhere: every token already issued for it
     * carries the old generation and authenticates nobody from the moment this
     * commits. Backs {@code /api/auth/logout}.
     */
    @Transactional
    public void revokeTokens(Long userId) {
        users.revokeTokensOf(userId);
    }
}
