package uz.wordbattle.user;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.List;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import uz.wordbattle.common.ApiException;

@Service
public class UserService {

    private final UserRepository users;

    public UserService(UserRepository users) {
        this.users = users;
    }

    @Transactional
    public User findOrCreateByTelegramId(long telegramId, String displayName) {
        return users.findByTelegramId(telegramId)
                .map(existing -> {
                    existing.setLastSeenAt(Instant.now());
                    return existing;
                })
                .orElseGet(() -> users.save(new User(telegramId, displayName)));
    }

    public User require(Long id) {
        return users.findById(id)
                .orElseThrow(() -> ApiException.notFound("user_not_found", "Foydalanuvchi topilmadi"));
    }

    public boolean nicknameTaken(String nickname) {
        return users.nicknameTaken(NicknamePolicy.normalise(nickname));
    }

    public List<String> suggestions(String nickname) {
        return NicknamePolicy.suggestions(nickname, this::nicknameTaken);
    }

    /**
     * Claims a nickname for the player. The unique index is the real arbiter —
     * two players sending the same name at the same moment both pass the
     * "is it free" check, and the loser gets a conflict here.
     */
    @Transactional
    public User claimNickname(Long userId, String rawNickname) {
        NicknamePolicy.Result result = NicknamePolicy.validate(rawNickname);
        if (result != NicknamePolicy.Result.OK) {
            throw ApiException.badRequest("nickname_invalid", NicknamePolicy.messageFor(result));
        }
        String nickname = NicknamePolicy.normalise(rawNickname);
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

    @Transactional
    public User updateCity(Long userId, String city) {
        User user = require(userId);
        user.setCity(city == null || city.isBlank() ? null : city.trim());
        return user;
    }

    public List<User> search(String query, Long excludeUserId, int limit) {
        String q = NicknamePolicy.normalise(query);
        if (q.isEmpty()) return List.of();
        return users.searchByNicknamePrefix(q, PageRequest.of(0, limit)).stream()
                .filter(u -> !u.getId().equals(excludeUserId))
                .toList();
    }

    public long rankOf(User user) {
        return users.rankOf(user.getRating());
    }

    /**
     * Daily streak bookkeeping: playing again the next calendar day extends it,
     * a gap resets it to one. Called once per finished match.
     */
    @Transactional
    public void touchStreak(User user, Instant playedAt) {
        LocalDate today = playedAt.atZone(ZoneOffset.UTC).toLocalDate();
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
        users.findById(userId).ifPresent(u -> u.setLastSeenAt(Instant.now()));
    }
}
