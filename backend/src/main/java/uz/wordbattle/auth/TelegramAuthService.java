package uz.wordbattle.auth;

import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Map;
import java.util.TreeMap;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Service;
import uz.wordbattle.common.ApiException;
import uz.wordbattle.config.AppProperties;

/**
 * Verifies the {@code initData} string a Telegram Mini App / Login Widget hands
 * to the client.
 *
 * <p>Telegram signs the payload with a key derived from the bot token, so the
 * server can trust the user id without ever talking to Telegram:
 * {@code secret = HMAC_SHA256("WebAppData", botToken)} and
 * {@code hash = HMAC_SHA256(secret, dataCheckString)}, where the check string is
 * every field except {@code hash}, sorted by key, joined with newlines.
 */
@Service
public class TelegramAuthService {

    private final AppProperties props;
    private final ObjectMapper mapper;

    public TelegramAuthService(AppProperties props, ObjectMapper mapper) {
        this.props = props;
        this.mapper = mapper;
    }

    public record TelegramUser(long id, String firstName, String lastName, String username) {
        public String displayName() {
            if (username != null && !username.isBlank()) return username;
            String name = firstName == null ? "" : firstName;
            if (lastName != null && !lastName.isBlank()) name = (name + " " + lastName).trim();
            return name.isBlank() ? "player" : name;
        }
    }

    public TelegramUser verify(String initData) {
        if (!props.telegram().configured()) {
            throw ApiException.unauthorized("telegram_disabled",
                    "Telegram bot tokeni sozlanmagan (TELEGRAM_BOT_TOKEN)");
        }
        if (initData == null || initData.isBlank()) {
            throw ApiException.badRequest("init_data_missing", "initData bo'sh");
        }

        Map<String, String> fields = parse(initData);
        String hash = fields.remove("hash");
        if (hash == null) {
            throw ApiException.unauthorized("init_data_invalid", "hash yo'q");
        }

        String checkString = new TreeMap<>(fields).entrySet().stream()
                .map(e -> e.getKey() + "=" + e.getValue())
                .reduce((a, b) -> a + "\n" + b)
                .orElse("");

        byte[] secret = hmac("WebAppData".getBytes(StandardCharsets.UTF_8),
                props.telegram().botToken().getBytes(StandardCharsets.UTF_8));
        String expected = hex(hmac(secret, checkString.getBytes(StandardCharsets.UTF_8)));

        if (!constantTimeEquals(expected, hash.toLowerCase())) {
            throw ApiException.unauthorized("init_data_invalid", "Imzo mos kelmadi");
        }

        String authDate = fields.get("auth_date");
        if (authDate != null && props.telegram().maxAge() != null) {
            Instant issued = Instant.ofEpochSecond(Long.parseLong(authDate));
            if (issued.plus(props.telegram().maxAge()).isBefore(Instant.now())) {
                throw ApiException.unauthorized("init_data_expired", "initData eskirgan");
            }
        }

        String userJson = fields.get("user");
        if (userJson == null) {
            throw ApiException.unauthorized("init_data_invalid", "user maydoni yo'q");
        }
        try {
            JsonNode node = mapper.readTree(userJson);
            return new TelegramUser(
                    node.path("id").asLong(),
                    node.path("first_name").asText(null),
                    node.path("last_name").asText(null),
                    node.path("username").asText(null));
        } catch (Exception e) {
            throw ApiException.unauthorized("init_data_invalid", "user maydonini o'qib bo'lmadi");
        }
    }

    private static Map<String, String> parse(String initData) {
        Map<String, String> out = new TreeMap<>();
        for (String pair : initData.split("&")) {
            int idx = pair.indexOf('=');
            if (idx <= 0) continue;
            String key = URLDecoder.decode(pair.substring(0, idx), StandardCharsets.UTF_8);
            String value = URLDecoder.decode(pair.substring(idx + 1), StandardCharsets.UTF_8);
            out.put(key, value);
        }
        return out;
    }

    static byte[] hmac(byte[] key, byte[] data) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(key, "HmacSHA256"));
            return mac.doFinal(data);
        } catch (Exception e) {
            throw new IllegalStateException("HMAC-SHA256 mavjud emas", e);
        }
    }

    static String hex(byte[] bytes) {
        StringBuilder sb = new StringBuilder(bytes.length * 2);
        for (byte b : bytes) sb.append(Character.forDigit((b >> 4) & 0xF, 16)).append(Character.forDigit(b & 0xF, 16));
        return sb.toString();
    }

    private static boolean constantTimeEquals(String a, String b) {
        if (a.length() != b.length()) return false;
        int diff = 0;
        for (int i = 0; i < a.length(); i++) diff |= a.charAt(i) ^ b.charAt(i);
        return diff == 0;
    }
}
