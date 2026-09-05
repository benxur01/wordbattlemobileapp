package uz.wordbattle.tournament;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.stream.IntStream;
import org.junit.jupiter.api.Test;

/**
 * The seat map alone, with no tournament, no players and no database — a
 * bracket's shape is a pure function of its size.
 */
class TournamentBracketTest {

    @Test
    void everySeedAppearsExactlyOnce() {
        for (int size : new int[] {4, 8, 16, 32}) {
            int[] order = TournamentBracket.seedOrder(size);
            assertThat(order).hasSize(size);
            Set<Integer> seeds = new HashSet<>();
            for (int seed : order) seeds.add(seed);
            assertThat(seeds).containsExactlyElementsOf(IntStream.rangeClosed(1, size).boxed().toList());
        }
    }

    /**
     * The pairing named in the brief: for 8 players, 1v8, 4v5, 3v6 and 2v7 —
     * the strongest seed can only meet the second strongest in the final, which
     * a naive 1v2/3v4 pairing would not guarantee.
     */
    @Test
    void eightPlayersPairTheStrongestAgainstTheWeakestEachMatch() {
        List<int[]> pairs = TournamentBracket.firstRoundPairs(8);
        assertThat(pairs).hasSize(4);

        Set<Set<Integer>> asSets = new HashSet<>();
        for (int[] pair : pairs) asSets.add(Set.of(pair[0], pair[1]));

        assertThat(asSets).containsExactlyInAnyOrder(
                Set.of(1, 8), Set.of(4, 5), Set.of(3, 6), Set.of(2, 7));
    }

    @Test
    void fourPlayersPairOneVsFourAndTwoVsThree() {
        List<int[]> pairs = TournamentBracket.firstRoundPairs(4);
        Set<Set<Integer>> asSets = new HashSet<>();
        for (int[] pair : pairs) asSets.add(Set.of(pair[0], pair[1]));
        assertThat(asSets).containsExactlyInAnyOrder(Set.of(1, 4), Set.of(2, 3));
    }

    /**
     * The two seeds that can only meet in the final never share a round-one or
     * round-two match, for every supported size — the property the recursive
     * reseeding exists to guarantee, checked generally rather than only on the
     * one size the brief spells out.
     */
    @Test
    void theTopTwoSeedsCanOnlyMeetInTheFinal() {
        for (int size : new int[] {8, 16, 32}) {
            int[] order = TournamentBracket.seedOrder(size);
            int indexOfOne = indexOf(order, 1);
            int indexOfTwo = indexOf(order, 2);
            // Two seeds meet in the final, and only the final, exactly when they
            // fall in different halves of the seed order.
            assertThat(indexOfOne < size / 2).isNotEqualTo(indexOfTwo < size / 2);
        }
    }

    @Test
    void roundsCountsUpToAndIncludingTheFinal() {
        assertThat(TournamentBracket.rounds(4)).isEqualTo(2);
        assertThat(TournamentBracket.rounds(8)).isEqualTo(3);
        assertThat(TournamentBracket.rounds(16)).isEqualTo(4);
        assertThat(TournamentBracket.rounds(32)).isEqualTo(5);
    }

    private static int indexOf(int[] order, int seed) {
        for (int i = 0; i < order.length; i++) {
            if (order[i] == seed) return i;
        }
        throw new AssertionError("seed " + seed + " missing from " + java.util.Arrays.toString(order));
    }
}
