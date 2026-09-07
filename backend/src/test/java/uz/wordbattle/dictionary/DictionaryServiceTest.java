package uz.wordbattle.dictionary;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

class DictionaryServiceTest {

    private static final int BOT_MIN_LENGTH = 4;

    /** {@code wordbattle.duel.words-to-win}: the most answers one duel can ask for. */
    private static final int WORDS_TO_WIN = 9;

    /** The shipped {@code wordbattle.duel.rare-letters}. */
    private static final Set<Character> RARE_LETTERS = Set.of('x', 'z');

    /**
     * One rating from each band {@code botMove} buckets into — see
     * {@code DictionaryService.Band}. {@code EVERYDAY} is the one the bot has
     * always played at, and every assertion about the pool itself is made
     * through it so that draining a letter still means what it used to.
     */
    private static final double GENTLE = 250;

    private static final double EVERYDAY = 600;

    private static final double SHARP = 1000;

    private static final double RARE = 1400;

    private static final double RAREST = 1900;

    private static DictionaryService dictionary;

    @BeforeAll
    static void loadOnce() throws IOException {
        dictionary = new DictionaryService();
        dictionary.load();
    }

    @Test
    void acceptsEverydayWordsIncludingShortOnes() {
        assertThat(List.of("cat", "dog", "run", "zoo", "axe", "ate", "sun", "eat"))
                .allSatisfy(word -> assertThat(dictionary.isValid(word)).as(word).isTrue());
    }

    @Test
    void acceptsShortWordsTheReferenceListsVouchFor() {
        // Thin, but real: "aah" and "qat" are in both Scrabble dictionaries, and
        // "zen" is everyday modern usage. Nobody types these by accident, so
        // they were deliberately left in rather than swept up with the junk.
        assertThat(List.of("aah", "aal", "qat", "zen"))
                .allSatisfy(word -> assertThat(dictionary.isValid(word)).as(word).isTrue());
    }

    @Test
    void rejectsThreeLetterEntriesThatAreNotWords() {
        // The whole point of invalid-en.txt: without it "aaa" walks past the
        // three-letter minimum and takes a turn.
        assertThat(List.of("aaa", "abc", "acc", "agt", "atm", "cpu", "dwt", "faq", "jan", "usa", "vip", "xyz"))
                .allSatisfy(word -> assertThat(dictionary.isValid(word)).as(word).isFalse());
    }

    @Test
    void botNeverAnswersWithAProperNoun() {
        Set<String> pool = botPoolFor('a');
        pool.addAll(botPoolFor('j'));
        pool.addAll(botPoolFor('l'));

        assertThat(pool)
                .doesNotContain("aaron", "aberdeen", "abraham", "adam", "africa", "april", "australia")
                .doesNotContain("japan", "java", "jerusalem", "john", "jordan", "july", "jesus")
                .doesNotContain("london", "louisiana", "luther", "latin", "lithuania");
        assertThat(pool).contains("apple", "autumn", "jacket", "journey", "letter", "light");
    }

    @Test
    void botNeverAnswersWithAnAbbreviation() {
        assertThat(botPoolFor('b')).doesNotContain("blvd", "biol", "bool");
        assertThat(botPoolFor('d')).doesNotContain("dept", "dist");
        assertThat(botPoolFor('m')).doesNotContain("misc", "mins", "mens");
    }

    @Test
    void keepsOrdinaryWordsThatDoubleAsNames() {
        // Filtering proper nouns must not cost the bot everyday vocabulary.
        assertThat(botPoolFor('m')).contains("march", "mark", "mason", "miller");
        assertThat(botPoolFor('r')).contains("robin", "rose", "ruby");
        assertThat(botPoolFor('j')).contains("jack", "jaguar", "jersey");
    }

    @Test
    void everyLetterTheBotCanBeSentToLastsAWholeDuel() {
        // One move was never the real bar. The trap is repetition: a player who
        // can keep steering the chain back to a thin letter empties the pool
        // and wins on NO_MOVES, and a duel is over after WORDS_TO_WIN words, so
        // that many answers per letter is exactly enough to see one out.
        // "x" and "z" are excused because the duel rules no longer send the bot
        // there at all — see DuelSession.requiredLetter().
        for (char letter = 'a'; letter <= 'z'; letter++) {
            if (RARE_LETTERS.contains(letter)) continue;
            assertThat(botPoolFor(letter))
                    .as("bot pool for '%s'", letter)
                    .hasSizeGreaterThanOrEqualTo(WORDS_TO_WIN);
        }
    }

    @Test
    void theRareLettersAreExactlyTheOnesTheBotCannotLast() {
        // The other end of the same claim, and the evidence for the shipped
        // wordbattle.duel.rare-letters: these two are thin enough to run out
        // inside a single duel, and nothing else in the alphabet is. If a
        // dictionary change ever fixes one of them, this fails and the letter
        // can come back into play.
        for (char letter : RARE_LETTERS) {
            assertThat(botPoolFor(letter)).as("bot pool for '%s'", letter).hasSizeLessThan(WORDS_TO_WIN);
        }
    }

    @Test
    void botMoveRespectsLengthAndTheUsedChain() {
        Set<String> used = new LinkedHashSet<>();
        for (int i = 0; i < 50; i++) {
            String word = dictionary.botMove('s', used, 6, EVERYDAY);
            assertThat(word).isNotNull();
            assertThat(word).startsWith("s").hasSizeGreaterThanOrEqualTo(6);
            assertThat(used.add(word)).as("%s repeated", word).isTrue();
        }
    }

    /**
     * The whole of the difficulty scale, in the only terms it is made of:
     * length, and which of the two pools the word came from. An approximation
     * — see {@code DictionaryService.Band} for why that is deliberate — so
     * what is held here is the ordering rather than any one number.
     */
    @Test
    void theBandsRunFromShortEverydayWordsToLongRareOnes() {
        // A letter with a fat pool on both sides, so that 80 answers per band
        // are drawn from choice rather than from what little was left.
        double gentle = averageLength(answers('s', GENTLE, 80));
        double everyday = averageLength(answers('s', EVERYDAY, 80));
        double sharp = averageLength(answers('s', SHARP, 80));
        double rarest = averageLength(answers('s', RAREST, 80));

        assertThat(gentle).as("a weak bot plays shorter words than the everyday one").isLessThan(everyday);
        assertThat(everyday).as("a strong bot plays longer words than the everyday one").isLessThan(sharp);
        assertThat(sharp).as("the hardest band plays the longest words").isLessThan(rarest);
    }

    @Test
    void theHardBandsAnswerFromOutsideTheEverydayPool() {
        Set<String> everyday = botPoolFor('c');

        assertThat(answers('c', RARE, 40)).doesNotContainAnyElementsOf(everyday);
        assertThat(answers('c', RAREST, 40)).doesNotContainAnyElementsOf(everyday);
    }

    /**
     * The one thing a band must never do. A bot with no legal answer hands the
     * duel to the human on the spot ({@code EndReason.NO_MOVES}), and a length
     * preference that could not be satisfied for some letter would trigger that
     * gift for no reason at all — so both ends of the scale are put in the
     * position their preference cannot be met in.
     */
    @Test
    void aBandsLengthPreferenceIsNeverAFilter() {
        Set<String> pool = botPoolFor('c');

        Set<String> shortOnesUsed = pool.stream()
                .filter(word -> word.length() <= 5)
                .collect(Collectors.toCollection(LinkedHashSet::new));
        String forGentle = dictionary.botMove('c', shortOnesUsed, BOT_MIN_LENGTH, GENTLE);
        assertThat(forGentle).as("a weak bot with no short word left").isNotNull();
        assertThat(forGentle).hasSizeGreaterThan(5);

        Set<String> longOnesUsed = pool.stream()
                .filter(word -> word.length() >= 7)
                .collect(Collectors.toCollection(LinkedHashSet::new));
        String forSharp = dictionary.botMove('c', longOnesUsed, BOT_MIN_LENGTH, SHARP);
        assertThat(forSharp).as("a strong bot with no long word left").isNotNull();
        assertThat(forSharp).hasSizeLessThan(7);
    }

    /**
     * The same tolerance one pool further out: "q" is the thinnest letter the
     * duel rules can hand the bot, and a chain that empties its long tail has
     * to leave it playing everyday words rather than stuck.
     */
    @Test
    void aHardBotFallsBackToTheEverydayPoolOnceTheRareOneIsDrained() {
        Set<String> everyday = botPoolFor('q');
        Set<String> served = new LinkedHashSet<>();

        String word;
        while ((word = dictionary.botMove('q', served, BOT_MIN_LENGTH, RAREST)) != null) {
            assertThat(served.add(word)).as("%s served twice", word).isTrue();
        }

        assertThat(served).as("the long tail was played first").hasSizeGreaterThan(everyday.size() * 2);
        assertThat(served).as("and the everyday pool after it").containsAll(everyday);
    }

    @Test
    void everyBandAnswersEveryLetterTheBotCanBeSentTo() {
        for (char letter = 'a'; letter <= 'z'; letter++) {
            if (RARE_LETTERS.contains(letter)) continue;
            for (double rating : new double[] {GENTLE, EVERYDAY, SHARP, RARE, RAREST}) {
                assertThat(dictionary.botMove(letter, Set.of(), BOT_MIN_LENGTH, rating))
                        .as("a bot at %s sent to '%s'", rating, letter)
                        .isNotNull();
            }
        }
    }

    @Test
    void hintsComeFromTheSameFilteredPool() {
        List<String> hints = dictionary.hints('a', Set.of(), 10);
        Set<String> pool = botPoolFor('a');

        assertThat(hints).hasSize(10).doesNotHaveDuplicates();
        assertThat(hints).allSatisfy(hint -> {
            assertThat(hint).startsWith("a").hasSizeGreaterThanOrEqualTo(4);
            assertThat(pool).contains(hint);
        });
    }

    @Test
    void playersMayStillUseProperNounsAndTechnicalTerms() {
        // The bot is held to a higher bar than the player on purpose: rejecting
        // a word someone actually typed is the more annoying failure.
        assertThat(List.of("aberdeen", "japan", "london", "aaron"))
                .allSatisfy(word -> assertThat(dictionary.isValid(word)).as(word).isTrue());
    }

    /** Drains {@code botMove} for one letter, which enumerates that letter's pool. */
    private Set<String> botPoolFor(char letter) {
        Set<String> used = new LinkedHashSet<>();
        String word;
        while ((word = dictionary.botMove(letter, used, BOT_MIN_LENGTH, EVERYDAY)) != null) {
            assertThat(used.add(word)).as("%s served twice", word).isTrue();
        }
        return used;
    }

    /** What a bot at {@code rating} actually answers with, over a fresh chain. */
    private List<String> answers(char letter, double rating, int count) {
        Set<String> used = new LinkedHashSet<>();
        List<String> words = new ArrayList<>(count);
        for (int i = 0; i < count; i++) {
            String word = dictionary.botMove(letter, used, BOT_MIN_LENGTH, rating);
            assertThat(word).as("a bot at %s ran out of '%s' words", rating, letter).isNotNull();
            used.add(word);
            words.add(word);
        }
        return words;
    }

    private double averageLength(List<String> words) {
        return words.stream().mapToInt(String::length).average().orElseThrow();
    }
}
