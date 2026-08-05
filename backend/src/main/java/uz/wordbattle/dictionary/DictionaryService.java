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
 * common-words subset the bot plays from so its moves stay natural.
 */
@Service
public class DictionaryService {

    private static final Logger log = LoggerFactory.getLogger(DictionaryService.class);

    private final Set<String> valid = new HashSet<>(400_000);
    private final Map<Character, List<String>> commonByFirstLetter = new ConcurrentHashMap<>();
    private final Random random = new Random();

    @PostConstruct
    void load() throws IOException {
        readLines("words/valid-en.txt", valid::add);

        List<String> common = new ArrayList<>();
        readLines("words/common-en.txt", common::add);
        for (String word : common) {
            commonByFirstLetter.computeIfAbsent(word.charAt(0), key -> new ArrayList<>()).add(word);
        }
        log.info("Dictionary loaded: {} valid words, {} common words", valid.size(), common.size());
    }

    private void readLines(String path, java.util.function.Consumer<String> consumer) throws IOException {
        try (InputStream in = new ClassPathResource(path).getInputStream();
                BufferedReader reader = new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                String word = line.trim().toLowerCase();
                if (!word.isEmpty()) consumer.accept(word);
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
