package uz.wordbattle.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.TreeMap;
import org.junit.jupiter.api.Test;
import uz.wordbattle.common.ApiException;
import uz.wordbattle.config.AppProperties;

class TelegramAuthServiceTest {

    private static final String BOT_TOKEN = "123456:AA-Test-Bot-Token";

    private TelegramAuthService service() {
        AppProperties props = new AppProperties(
                new AppProperties.Jwt("x".repeat(32), Duration.ofDays(1), "test"),
                new AppProperties.Telegram(BOT_TOKEN, Duration.ofHours(24)),
                new AppProperties.Duel(15, 3, 9, 12),
                new AppProperties.Matchmaking(75, 25, 400, 3, 12),
                true);
        return new TelegramAuthService(props, new ObjectMapper());
    }

    /** Builds initData exactly the way Telegram signs it. */
    private String signedInitData(long userId, Instant authDate) {
        Map<String, String> fields = new LinkedHashMap<>();
        fields.put("auth_date", String.valueOf(authDate.getEpochSecond()));
        fields.put("query_id", "AAE");
        fields.put("user", "{\"id\":" + userId + ",\"first_name\":\"Jasur\",\"username\":\"jasur_07\"}");

        String checkString = new TreeMap<>(fields).entrySet().stream()
                .map(e -> e.getKey() + "=" + e.getValue())
                .reduce((a, b) -> a + "\n" + b)
                .orElseThrow();

        byte[] secret = TelegramAuthService.hmac(
                "WebAppData".getBytes(StandardCharsets.UTF_8), BOT_TOKEN.getBytes(StandardCharsets.UTF_8));
        String hash = TelegramAuthService.hex(
                TelegramAuthService.hmac(secret, checkString.getBytes(StandardCharsets.UTF_8)));

        StringBuilder query = new StringBuilder();
        fields.forEach((key, value) -> query
                .append(query.isEmpty() ? "" : "&")
                .append(key)
                .append('=')
                .append(URLEncoder.encode(value, StandardCharsets.UTF_8)));
        return query.append("&hash=").append(hash).toString();
    }

    @Test
    void acceptsDataSignedWithTheBotToken() {
        var user = service().verify(signedInitData(4242L, Instant.now()));

        assertThat(user.id()).isEqualTo(4242L);
        assertThat(user.displayName()).isEqualTo("jasur_07");
    }

    @Test
    void rejectsATamperedUserId() {
        String initData = signedInitData(4242L, Instant.now()).replace("4242", "9999");

        assertThatThrownBy(() -> service().verify(initData))
                .isInstanceOf(ApiException.class)
                .hasMessageContaining("Imzo");
    }

    @Test
    void rejectsStaleData() {
        String initData = signedInitData(4242L, Instant.now().minus(Duration.ofDays(2)));

        assertThatThrownBy(() -> service().verify(initData))
                .isInstanceOf(ApiException.class)
                .hasMessageContaining("eskirgan");
    }

    @Test
    void rejectsMissingHash() {
        assertThatThrownBy(() -> service().verify("auth_date=1&user=%7B%7D"))
                .isInstanceOf(ApiException.class);
    }
}
