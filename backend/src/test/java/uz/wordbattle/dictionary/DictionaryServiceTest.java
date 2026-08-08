package uz.wordbattle.dictionary;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

class DictionaryServiceTest {

    private static final int BOT_MIN_LENGTH = 4;

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
    void everyLetterStillLeavesTheBotAMove() {
        // A letter with an empty pool hands the human a free win, so the
        // exclusion lists must never empty one out.
        for (char letter = 'a'; letter <= 'z'; letter++) {
            assertThat(dictionary.botMove(letter, Set.of(), BOT_MIN_LENGTH))
                    .as("bot move for '%s'", letter)
                    .isNotNull();
        }
    }

    @Test
    void botMoveRespectsLengthAndTheUsedChain() {
        Set<String> used = new LinkedHashSet<>();
        for (int i = 0; i < 50; i++) {
            String word = dictionary.botMove('s', used, 6);
            assertThat(word).isNotNull();
            assertThat(word).startsWith("s").hasSizeGreaterThanOrEqualTo(6);
            assertThat(used.add(word)).as("%s repeated", word).isTrue();
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
        while ((word = dictionary.botMove(letter, used, BOT_MIN_LENGTH)) != null) {
            assertThat(used.add(word)).as("%s served twice", word).isTrue();
        }
        return used;
    }
}
