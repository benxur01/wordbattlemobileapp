package uz.wordbattle.dictionary;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Service;

/**
 * The authority on what counts as an English word. Kept server-side on purpose:
 * when the client decides validity, any modified build can play anything.
 *
 * <p>Two lists are loaded — a large one for accepting player words, and a
 * common-words subset the bot plays from so its moves stay natural. Both come
 * from third-party sources that carry entries this game should not use, so two
 * hand-curated exclusion lists are subtracted on top: {@code invalid-en.txt}
 * (abbreviations and unit symbols that are not words at all) applies to
 * everything, and {@code bot-excluded-en.txt} (proper nouns) applies only to the
 * bot's pool — the bot answering "aberdeen" reads as a bug, whereas rejecting a
 * player for it would only be pedantic.
 */
@Service
public class DictionaryService {

    private static final Logger log = LoggerFactory.getLogger(DictionaryService.class);

    private final Set<String> valid = new HashSet<>(400_000);
    private final Map<Character, List<String>> commonByFirstLetter = new ConcurrentHashMap<>();
    private final Random random = new Random();

    @PostConstruct
    void load() throws IOException {
        Set<String> notWords = new HashSet<>();
        readLines("words/invalid-en.txt", notWords::add);
        Set<String> offLimitsToBot = new HashSet<>(notWords);
        readLines("words/bot-excluded-en.txt", offLimitsToBot::add);

        readLines("words/valid-en.txt", valid::add);
        int loaded = valid.size();
        valid.removeAll(notWords);

        int common = 0;
        List<String> pool = new ArrayList<>();
        readLines("words/common-en.txt", pool::add);
        for (String word : pool) {
            if (offLimitsToBot.contains(word)) continue;
            commonByFirstLetter.computeIfAbsent(word.charAt(0), key -> new ArrayList<>()).add(word);
            common++;
        }
        log.info(
                "Dictionary loaded: {} valid words ({} excluded), {} bot words ({} excluded)",
                valid.size(),
                loaded - valid.size(),
                common,
                pool.size() - common);
    }

    private void readLines(String path, java.util.function.Consumer<String> consumer) throws IOException {
        try (InputStream in = new ClassPathResource(path).getInputStream();
                BufferedReader reader = new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                String word = line.trim().toLowerCase();
                // '#' starts a comment: the exclusion lists carry a header
                // explaining how they were derived.
                if (!word.isEmpty() && word.charAt(0) != '#') consumer.accept(word);
            }
        }
    }

    public boolean isValid(String word) {
        return word != null && valid.contains(word.toLowerCase());
    }

    public int size() {
        return valid.size();
    }

    /**
     * A word the bot can answer with: starts with {@code letter}, long enough to
     * be interesting, and not already in the chain.
     */
    public String botMove(char letter, Collection<String> used, int minLength) {
        List<String> pool = commonByFirstLetter.getOrDefault(letter, List.of());
        if (pool.isEmpty()) return null;
        // Sample a handful of random spots before falling back to a full scan,
        // so the common case stays O(1) on a list of thousands.
        for (int attempt = 0; attempt < 24; attempt++) {
            String candidate = pool.get(random.nextInt(pool.size()));
            if (candidate.length() >= minLength && !used.contains(candidate)) return candidate;
        }
        for (String candidate : pool) {
            if (candidate.length() >= minLength && !used.contains(candidate)) return candidate;
        }
        return null;
    }

    /** Suggestions for the practice screen's hint button and the lose screen. */
    public List<String> hints(char letter, Collection<String> used, int limit) {
        List<String> pool = commonByFirstLetter.getOrDefault(letter, List.of());
        List<String> out = new ArrayList<>(limit);
        for (String candidate : pool) {
            if (candidate.length() >= 4 && !used.contains(candidate)) {
                out.add(candidate);
                if (out.size() == limit) break;
            }
        }
        return out;
    }
}
