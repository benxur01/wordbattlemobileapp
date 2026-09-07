package uz.wordbattle.dictionary;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.springframework.core.io.ClassPathResource;
import uz.wordbattle.match.DuelSession;

/**
 * The themed word lists, which are the whole of what a themed duel is: both
 * sides play out of one of these instead of out of the dictionary.
 *
 * <p>Two things are being held here. The first is that a theme is a slice of
 * the game's own vocabulary rather than a second dictionary smuggled in beside
 * it — every word in one is a word the server already accepted before themes
 * existed. The second is that a chain inside a few hundred words still has
 * somewhere to go on every turn: the dictionary can afford a letter it is thin
 * on, a theme cannot, and the letters a theme cannot answer are handed over the
 * way "x" and "z" already are rather than left for whoever is on turn to lose
 * to.
 */
class ThemedWordListTest {

    /** {@code wordbattle.duel.min-word-length} plus one — see the bot's move. */
    private static final int BOT_MIN_LENGTH = 4;

    /** The shipped {@code wordbattle.duel.rare-letters}. */
    private static final Set<Character> RARE_LETTERS = Set.of('x', 'z');

    /** {@code DictionaryService.THEME_ANSWERS_PER_LETTER}. */
    private static final int ANSWERS_PER_LETTER = 5;

    /**
     * The floor a theme has to clear to be worth offering at all. Well under
     * what the shipped lists carry, so this fails for a theme that was gutted
     * rather than for one that is merely on the small side.
     */
    private static final int SMALLEST_USEFUL_THEME = 150;

    /** One rating from each band, as {@code DictionaryServiceTest} names them. */
    private static final double GENTLE = 250;

    private static final double EVERYDAY = 600;

    private static final double SHARP = 1000;

    private static final double RARE = 1400;

    private static final double RAREST = 1900;

    /**
     * The themes the difficulty ordering is read off. Every theme is walked by
     * the tests above it; this one is a measurement rather than a rule, and two
     * themes with vocabulary this deep say more about it than eight averages
     * taken over whatever each list happens to hold.
     */
    private static final List<WordTheme> CORE = List.of(WordTheme.ANIMALS, WordTheme.FOOD);

    private static DictionaryService dictionary;

    @BeforeAll
    static void loadOnce() throws IOException {
        dictionary = new DictionaryService();
        dictionary.load();
    }

    @Test
    void everyThemedWordIsOneTheGameAlreadyAccepted() {
        for (WordTheme theme : WordTheme.values()) {
            for (String word : wordsOf(theme)) {
                assertThat(dictionary.isValid(word))
                        .as("'%s' is in the %s list but not in the dictionary", word, theme.id())
                        .isTrue();
                assertThat(dictionary.isInTheme(theme, word)).as("%s: %s", theme.id(), word).isTrue();
            }
        }
    }

    @Test
    void everyThemeIsBigEnoughToBeWorthOffering() {
        for (WordTheme theme : WordTheme.values()) {
            assertThat(wordsOf(theme)).as("the %s list", theme.id()).hasSizeGreaterThan(SMALLEST_USEFUL_THEME);
        }
    }

    @Test
    void aThemedBotNeverAnswersFromOutsideItsTheme() {
        for (WordTheme theme : WordTheme.values()) {
            for (char letter = 'a'; letter <= 'z'; letter++) {
                for (double rating : new double[] {GENTLE, EVERYDAY, SHARP, RARE, RAREST}) {
                    for (String word : drain(theme, letter, rating)) {
                        assertThat(dictionary.isInTheme(theme, word))
                                .as("a %s bot at %s answered '%s'", theme.id(), rating, word)
                                .isTrue();
                    }
                }
            }
        }
    }

    @Test
    void aThemedBotAnswersEveryLetterTheChainCanHandItAtEveryStrength() {
        for (WordTheme theme : WordTheme.values()) {
            for (char letter : playableLetters(theme)) {
                for (double rating : new double[] {GENTLE, EVERYDAY, SHARP, RARE, RAREST}) {
                    assertThat(dictionary.botMove(theme, letter, Set.of(), BOT_MIN_LENGTH, rating))
                            .as("a %s bot at %s sent to '%s'", theme.id(), rating, letter)
                            .isNotNull();
                }
            }
        }
    }

    /**
     * The claim behind {@link #playableLetters}: a letter is skipped when the
     * theme cannot answer it and only then. Without the first half a theme
     * could be handed a letter it has one word for; without the second it could
     * quietly stop using letters it is perfectly good at.
     */
    @Test
    void theSkippedLettersAreExactlyTheOnesTheThemeCannotAnswer() {
        for (WordTheme theme : WordTheme.values()) {
            Set<Character> skipped = dictionary.thinLetters(theme);
            for (char letter = 'a'; letter <= 'z'; letter++) {
                int answers = drain(theme, letter, EVERYDAY).size();
                assertThat(skipped.contains(letter))
                        .as("%s has %d answers for '%s'", theme.id(), answers, letter)
                        .isEqualTo(answers < ANSWERS_PER_LETTER);
            }
        }
    }

    /**
     * The dead-end sweep, and the reason a themed duel is playable at all.
     *
     * <p>Every word either side can say is walked through the rule that decides
     * what the next player is asked for — {@link DuelSession#requiredLetter()},
     * the real one rather than a copy of it — and the letter it hands over has
     * to be one this theme can answer. A theme that fails this has a word in it
     * that ends the duel for whoever plays it, which reads as the game breaking
     * rather than as anybody winning.
     *
     * <p>The seed words are walked too: the chain's first letter comes from one
     * of those and from nothing in the theme at all.
     */
    @Test
    void noThemeLeavesAChainWithNowhereToGo() {
        for (WordTheme theme : WordTheme.values()) {
            Set<Character> playable = new HashSet<>(playableLetters(theme));
            List<String> words = new ArrayList<>(wordsOf(theme));
            words.addAll(seedWords());

            for (String word : words) {
                char next = handedOverBy(theme, word);
                assertThat(playable).as("'%s' leaves the %s chain on '%s'", word, theme.id(), next).contains(next);
            }
        }
    }

    /**
     * Theme and strength are two choices, not one: inside the same theme, the
     * bot a player asked to make it hard still answers with the longer, rarer
     * end of that theme's vocabulary. The ordering is what is held, the same
     * way {@code DictionaryServiceTest} holds it for the whole dictionary —
     * a theme is a few hundred words and no particular gap between two bands
     * would mean anything.
     */
    @Test
    void theBandsStillOrderTheWordsInsideATheme() {
        for (WordTheme theme : CORE) {
            char letter = fattestLetter(theme);
            double gentle = averageLength(sample(theme, letter, GENTLE, 40));
            double rarest = averageLength(sample(theme, letter, RAREST, 40));

            assertThat(gentle)
                    .as("%s: a weak bot plays shorter '%s' words than the hardest one", theme.id(), letter)
                    .isLessThan(rarest);
        }
    }

    // --------------------------------------------------------------- helpers

    /** The theme's list as it ships, read the way the service reads it. */
    private static Set<String> wordsOf(WordTheme theme) {
        Set<String> words = new LinkedHashSet<>();
        try (InputStream in = new ClassPathResource(theme.resource()).getInputStream();
                BufferedReader reader = new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                String word = line.trim().toLowerCase();
                if (!word.isEmpty() && word.charAt(0) != '#') words.add(word);
            }
        } catch (IOException e) {
            throw new AssertionError("The " + theme.id() + " list could not be read", e);
        }
        return words;
    }

    /** {@code DuelService.SEED_WORDS} — the chain's opening word. */
    private static List<String> seedWords() {
        return List.of("battle", "silver", "planet", "candle", "forest", "market", "window", "garden");
    }

    /** Every letter a themed chain can be left standing on. */
    private List<Character> playableLetters(WordTheme theme) {
        List<Character> letters = new ArrayList<>();
        for (char letter = 'a'; letter <= 'z'; letter++) {
            if (RARE_LETTERS.contains(letter) || dictionary.thinLetters(theme).contains(letter)) continue;
            letters.add(letter);
        }
        return letters;
    }

    /** The letter this word hands to whoever answers it, inside this theme. */
    private char handedOverBy(WordTheme theme, String word) {
        Set<Character> skipped = new HashSet<>(RARE_LETTERS);
        skipped.addAll(dictionary.thinLetters(theme));
        return new DuelSession("test", 1L, DuelSession.BOT_ID, true, EVERYDAY, theme, word, skipped).requiredLetter();
    }

    /** Drains one letter's themed pool at one band, which enumerates it. */
    private Set<String> drain(WordTheme theme, char letter, double rating) {
        Set<String> served = new LinkedHashSet<>();
        String word;
        while ((word = dictionary.botMove(theme, letter, served, BOT_MIN_LENGTH, rating)) != null) {
            assertThat(served.add(word)).as("%s served twice", word).isTrue();
        }
        return served;
    }

    /**
     * What a themed bot at {@code rating} answers one letter with, each answer
     * taken over an empty chain.
     *
     * <p>Empty rather than accumulating, which is how the same measurement is
     * made for the whole dictionary: a letter there holds thousands of words
     * and 80 of them barely touch it, where a theme holds a few dozen and a
     * band asked for all of them ends up reporting the pool's own average
     * instead of its preference.
     */
    private List<String> sample(WordTheme theme, char letter, double rating, int count) {
        List<String> words = new ArrayList<>(count);
        for (int i = 0; i < count; i++) {
            String word = dictionary.botMove(theme, letter, Set.of(), BOT_MIN_LENGTH, rating);
            assertThat(word).as("a %s bot at %s has no '%s' word", theme.id(), rating, letter).isNotNull();
            words.add(word);
        }
        return words;
    }

    /**
     * The letter this theme has most words for, so the bands above are compared
     * over answers drawn from choice rather than from what little was left.
     */
    private char fattestLetter(WordTheme theme) {
        char fattest = 'a';
        int most = 0;
        for (char letter = 'a'; letter <= 'z'; letter++) {
            int answers = drain(theme, letter, EVERYDAY).size();
            if (answers > most) {
                most = answers;
                fattest = letter;
            }
        }
        return fattest;
    }

    private double averageLength(List<String> words) {
        return words.stream().mapToInt(String::length).average().orElseThrow();
    }
}
