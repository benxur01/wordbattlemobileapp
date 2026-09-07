package uz.wordbattle.dictionary;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collection;
import java.util.EnumMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
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
 *
 * <p>What is left of the large list once the common subset and the proper nouns
 * are taken out of it is indexed as well, as the pool a strong bot answers from
 * — see {@link Band}.
 *
 * <p>Alongside all three sits one small word list per {@link WordTheme}, for
 * the duels a player asks to play inside a single topic — see
 * {@link ThemePool}.
 */
@Service
public class DictionaryService {

    private static final Logger log = LoggerFactory.getLogger(DictionaryService.class);

    /**
     * How many answers a letter needs before a themed chain may be left
     * standing on it. A theme is a few hundred words rather than 358k, so some
     * letter of every one of them is thin — and a letter with one answer is a
     * dead end the moment that answer has been played, which in a themed duel
     * would be most duels. Letters below this are handed over instead of played
     * on; see {@link #thinLetters}.
     */
    private static final int THEME_ANSWERS_PER_LETTER = 5;

    /**
     * The shortest word the bot is ever asked for — {@code
     * wordbattle.duel.min-word-length} plus one, see {@code
     * DuelService.playBotMove}. Only {@link #thinLetters} needs it, to count a
     * letter's answers the way the bot will actually be able to use them: a
     * letter served by nothing but three-letter words is one the bot is stuck
     * on however many of them there are.
     */
    private static final int SHORTEST_BOT_WORD = 4;

    private final Set<String> valid = new HashSet<>(400_000);
    private final Map<Character, List<String>> commonByFirstLetter = new ConcurrentHashMap<>();

    /**
     * Everything the bot may play that is <em>not</em> in the common subset:
     * the long tail of the dictionary, which is where a strong bot's words come
     * from. Same exclusions as the common pool — a rare proper noun is no more
     * playable than a familiar one.
     */
    private final Map<Character, List<String>> rareByFirstLetter = new ConcurrentHashMap<>();

    private final Map<WordTheme, ThemePool> themePools = new EnumMap<>(WordTheme.class);

    private final Random random = new Random();

    /**
     * One theme's vocabulary. {@code words} is the whole of what either side
     * may say in a duel restricted to it; the two indexes are the same list
     * split for the bot exactly as {@link #commonByFirstLetter} and
     * {@link #rareByFirstLetter} split the dictionary, so the difficulty bands
     * go on meaning inside a theme what they mean outside it.
     */
    private record ThemePool(
            Set<String> words,
            Map<Character, List<String>> commonByFirstLetter,
            Map<Character, List<String>> rareByFirstLetter,
            Set<Character> thinLetters) {}

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
        Set<String> commonWords = new HashSet<>(pool);
        for (String word : pool) {
            if (offLimitsToBot.contains(word)) continue;
            commonByFirstLetter.computeIfAbsent(word.charAt(0), key -> new ArrayList<>()).add(word);
            common++;
        }

        int rare = 0;
        for (String word : valid) {
            // The whole common list is subtracted, including the entries it
            // lost to the exclusions: a word kept out of the bot's easy pool
            // for being a proper noun must not reappear in its hard one.
            if (commonWords.contains(word) || offLimitsToBot.contains(word)) continue;
            rareByFirstLetter.computeIfAbsent(word.charAt(0), key -> new ArrayList<>()).add(word);
            rare++;
        }

        log.info(
                "Dictionary loaded: {} valid words ({} excluded), {} bot words ({} excluded), {} rare bot words",
                valid.size(),
                loaded - valid.size(),
                common,
                pool.size() - common,
                rare);

        for (WordTheme theme : WordTheme.values()) {
            ThemePool themed = loadTheme(theme, commonWords, offLimitsToBot);
            themePools.put(theme, themed);
            log.info(
                    "Theme '{}' loaded: {} words, letters it cannot answer: {}",
                    theme.id(),
                    themed.words().size(),
                    themed.thinLetters());
        }
    }

    /**
     * One theme's list, read like the others and split against the pools above
     * rather than by any judgement of its own: a themed word the dictionary
     * already counts as everyday is the easy bot's, the rest are the hard
     * bot's. The exclusions apply here too — a proper noun is no more the
     * bot's to play inside a theme than outside one.
     */
    private ThemePool loadTheme(WordTheme theme, Set<String> commonWords, Set<String> offLimitsToBot)
            throws IOException {
        // Insertion-ordered so the pools follow the file, which is sorted:
        // hints() reads the front of one and would otherwise offer a different
        // three words for the same letter on every restart.
        Set<String> words = new LinkedHashSet<>();
        readLines(theme.resource(), words::add);

        Map<Character, List<String>> common = new ConcurrentHashMap<>();
        Map<Character, List<String>> rare = new ConcurrentHashMap<>();
        for (String word : words) {
            if (offLimitsToBot.contains(word)) continue;
            Map<Character, List<String>> target = commonWords.contains(word) ? common : rare;
            target.computeIfAbsent(word.charAt(0), key -> new ArrayList<>()).add(word);
        }

        Set<Character> thin = new HashSet<>();
        for (char letter = 'a'; letter <= 'z'; letter++) {
            if (answersFor(letter, common) + answersFor(letter, rare) < THEME_ANSWERS_PER_LETTER) {
                thin.add(letter);
            }
        }
        return new ThemePool(Set.copyOf(words), common, rare, Set.copyOf(thin));
    }

    private long answersFor(char letter, Map<Character, List<String>> pool) {
        return pool.getOrDefault(letter, List.of()).stream()
                .filter(word -> word.length() >= SHORTEST_BOT_WORD)
                .count();
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

    /**
     * The same question inside one theme, and the whole of what a themed duel
     * asks: every themed list is a subset of {@link #valid}, so a word this
     * accepts is a word the dictionary accepts as well.
     */
    public boolean isInTheme(WordTheme theme, String word) {
        return word != null && themePools.get(theme).words().contains(word.toLowerCase());
    }

    /**
     * The letters this theme has too few answers for — see
     * {@link #THEME_ANSWERS_PER_LETTER}. A themed duel adds them to the rare
     * letters the rules already step over, so a chain ending on one hands over
     * the letter before it instead of leaving whoever is on turn with nothing
     * legal to say. {@code DuelSession.requiredLetter()} is the rule; this is
     * only the list of letters it applies to.
     */
    public Set<Character> thinLetters(WordTheme theme) {
        return themePools.get(theme).thinLetters();
    }

    public int size() {
        return valid.size();
    }

    /**
     * How hard the bot's words are meant to feel, as a band of the rating its
     * duel is being played at.
     *
     * <p>An approximation, and deliberately so. Nothing in these word lists
     * carries a difficulty — there is no CEFR grade, no frequency count,
     * nothing but the words themselves — and classifying 358k of them properly
     * is a project rather than a feature. What is already to hand is the split
     * the lists make (a curated everyday subset against the long tail behind
     * it) and the length of the word, and between them those two order words
     * roughly the way a player would: short familiar ones are easy, long ones
     * out of the far end of the dictionary are not. That is all a band is, and
     * it is never shown to the player as anything but the rating they chose.
     *
     * <p>{@link #EVEN} is what the bot has always played and is left exactly
     * as it was. The fallback bot arrives at the human's own rating plus a
     * little, which for everyday accounts lands in this band, and that duel has
     * to feel the way it did before any of this existed.
     */
    private enum Band {
        GENTLE(false, 0, 5),
        EVEN(false, 0, Integer.MAX_VALUE),
        SHARP(false, 7, Integer.MAX_VALUE),
        RARE(true, 8, Integer.MAX_VALUE),
        RAREST(true, 11, Integer.MAX_VALUE);

        private final boolean rarePool;
        private final int preferredMin;
        private final int preferredMax;

        Band(boolean rarePool, int preferredMin, int preferredMax) {
            this.rarePool = rarePool;
            this.preferredMin = preferredMin;
            this.preferredMax = preferredMax;
        }

        static Band of(double rating) {
            if (rating < 400) return GENTLE;
            if (rating < 800) return EVEN;
            if (rating < 1200) return SHARP;
            if (rating < 1600) return RARE;
            return RAREST;
        }

        boolean prefers(String word) {
            return word.length() >= preferredMin && word.length() <= preferredMax;
        }
    }

    /**
     * A word the bot can answer with: starts with {@code letter}, long enough to
     * be interesting, and not already in the chain.
     *
     * <p>{@code botRating} is the rating this duel's bot is playing at — the
     * fallback bot's, which tracks the human's own, or the one the player picked
     * for themselves — and it decides which pool the answer is drawn from and
     * which lengths are preferred inside it. Preferred, not required: a bot with
     * no legal answer hands the duel to the human on the spot, and a length that
     * happens to be unsatisfiable for some letter must never be what does that.
     * See {@link #pick}, and {@code DuelService.playBotMove} for the other end.
     */
    public String botMove(char letter, Collection<String> used, int minLength, double botRating) {
        Band band = Band.of(botRating);
        if (band.rarePool) {
            String rare = pick(rareByFirstLetter.getOrDefault(letter, List.of()), used, minLength, band);
            if (rare != null) return rare;
        }
        // The everyday pool serves the easy bands, and stands behind the hard
        // ones for the letter whose long tail is spent — a chain can be steered
        // back to the same letter all duel, and a hard bot that ran out there
        // would be handing over a win the rules never meant it to.
        return pick(commonByFirstLetter.getOrDefault(letter, List.of()), used, minLength, band);
    }

    /**
     * The bot's answer from inside one theme. The band picks which of the
     * theme's two pools is tried first, so a themed duel is still played at the
     * strength that was asked for — the strong bot reaches for the theme's
     * longer, rarer words, the weak one for its everyday ones.
     *
     * <p>Here each pool stands behind the other, where the whole dictionary
     * only has the everyday one standing behind the long tail. A theme is a few
     * hundred words: a letter whose everyday half is empty is ordinary rather
     * than a sign of anything, and an easy bot that treated it as the end of
     * its options would hand over duels it had barely started.
     */
    public String botMove(WordTheme theme, char letter, Collection<String> used, int minLength, double botRating) {
        ThemePool pool = themePools.get(theme);
        Band band = Band.of(botRating);
        List<String> common = pool.commonByFirstLetter().getOrDefault(letter, List.of());
        List<String> rare = pool.rareByFirstLetter().getOrDefault(letter, List.of());

        String word = pick(band.rarePool ? rare : common, used, minLength, band);
        return word != null ? word : pick(band.rarePool ? common : rare, used, minLength, band);
    }

    /**
     * The best legal word a few random draws can find, or any legal word at all
     * if that fails.
     *
     * <p>Sampling a handful of spots before falling back to a full scan keeps
     * the common case O(1) on a list of thousands. The band's preference rides
     * along on that: a draw inside it is taken at once, a legal draw outside it
     * is held on to in case nothing better turns up, and the scan at the end
     * ignores the preference entirely — by then the question is no longer which
     * word is best but whether there is one at all.
     */
    private String pick(List<String> pool, Collection<String> used, int minLength, Band band) {
        if (pool.isEmpty()) return null;
        String settleFor = null;
        for (int attempt = 0; attempt < 24; attempt++) {
            String candidate = pool.get(random.nextInt(pool.size()));
            if (candidate.length() < minLength || used.contains(candidate)) continue;
            if (band.prefers(candidate)) return candidate;
            if (settleFor == null) settleFor = candidate;
        }
        if (settleFor != null) return settleFor;
        for (String candidate : pool) {
            if (candidate.length() >= minLength && !used.contains(candidate)) return candidate;
        }
        return null;
    }

    /** Suggestions for the practice screen's hint button and the lose screen. */
    public List<String> hints(char letter, Collection<String> used, int limit) {
        List<String> out = new ArrayList<>(limit);
        addHints(commonByFirstLetter.getOrDefault(letter, List.of()), used, limit, out);
        return out;
    }

    /**
     * The same suggestions for a themed duel, which has to take both of the
     * theme's pools: the everyday one holds a handful of words per letter at
     * best, and a lose screen that offered the player words their own duel
     * would have refused is worse than one that offers none.
     */
    public List<String> hints(WordTheme theme, char letter, Collection<String> used, int limit) {
        ThemePool pool = themePools.get(theme);
        List<String> out = new ArrayList<>(limit);
        addHints(pool.commonByFirstLetter().getOrDefault(letter, List.of()), used, limit, out);
        addHints(pool.rareByFirstLetter().getOrDefault(letter, List.of()), used, limit, out);
        return out;
    }

    private void addHints(List<String> pool, Collection<String> used, int limit, List<String> out) {
        for (String candidate : pool) {
            if (out.size() == limit) return;
            if (candidate.length() >= 4 && !used.contains(candidate)) out.add(candidate);
        }
    }
}
