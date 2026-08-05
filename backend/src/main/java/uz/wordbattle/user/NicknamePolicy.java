package uz.wordbattle.user;

import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * The nickname rules the onboarding screen shows: 3–16 characters, latin
 * letters, digits, underscore and dot. Enforced here so the client cannot skip
 * them.
 */
public final class NicknamePolicy {

    public static final int MIN_LENGTH = 3;
    public static final int MAX_LENGTH = 16;

    private static final Pattern ALLOWED = Pattern.compile("^[a-z0-9_.]+$");

    /** Names the game keeps for itself. */
    private static final Set<String> RESERVED = Set.of(
            "admin", "administrator", "wordbattle", "word_battle", "support", "system", "moderator", "bot", "root");

    private NicknamePolicy() {}

    public enum Result { OK, TOO_SHORT, TOO_LONG, BAD_CHARACTERS, RESERVED }

    public static String normalise(String raw) {
        return raw == null ? "" : raw.trim().toLowerCase();
    }

    public static Result validate(String raw) {
        String value = normalise(raw);
        if (value.length() < MIN_LENGTH) return Result.TOO_SHORT;
        if (value.length() > MAX_LENGTH) return Result.TOO_LONG;
        if (!ALLOWED.matcher(value).matches()) return Result.BAD_CHARACTERS;
        if (RESERVED.contains(value)) return Result.RESERVED;
        return Result.OK;
    }

    public static String messageFor(Result result) {
        return switch (result) {
            case OK -> "";
            case TOO_SHORT -> "Kamida " + MIN_LENGTH + " ta belgi";
            case TOO_LONG -> "Ko'pi bilan " + MAX_LENGTH + " ta belgi";
            case BAD_CHARACTERS -> "Faqat lotin harflari, raqam, _ va .";
            case RESERVED -> "Bu taxallus band";
        };
    }

    /** Free-looking alternatives offered when the wanted nickname is taken. */
    public static List<String> suggestions(String raw, java.util.function.Predicate<String> taken) {
        String base = normalise(raw);
        List<String> candidates = new ArrayList<>();
        candidates.add(trim(base + "_uz"));
        candidates.add(trim("the_" + base));
        for (int i = 1; i <= 99 && candidates.size() < 6; i++) {
            candidates.add(trim(base + (i * 7 + 10)));
        }
        List<String> free = new ArrayList<>();
        for (String candidate : candidates) {
            if (validate(candidate) == Result.OK && !taken.test(candidate) && !free.contains(candidate)) {
                free.add(candidate);
            }
            if (free.size() == 3) break;
        }
        return free;
    }

    private static String trim(String value) {
        return value.length() <= MAX_LENGTH ? value : value.substring(0, MAX_LENGTH);
    }
}
