package uz.wordbattle.tournament;

import java.util.ArrayList;
import java.util.List;

/**
 * The seat map every bracket in this feature is built from: which seed plays
 * which seed in round one, arranged so that two players can only meet as early
 * as their seeds force them to — the strongest cannot meet the second
 * strongest before the final, the way a fixed 1v2/3v4 pairing would let
 * happen.
 *
 * <p>Pure and stateless on purpose: seeding is a function of the bracket size
 * alone, so it is tested without a database or a tournament to seed.
 */
final class TournamentBracket {

    private TournamentBracket() {}

    /**
     * The classic recursive reseeding used by every standard elimination
     * bracket: for size 8 it produces {@code [1, 8, 4, 5, 2, 7, 3, 6]}, whose
     * consecutive pairs are round one's four matches — 1v8, 4v5, 2v7, 3v6, the
     * same pairing the top seed can never see the second seed before the final.
     *
     * @param size a power of two
     * @return seeds 1..size, in bracket-slot order
     */
    static int[] seedOrder(int size) {
        int[] order = {1};
        while (order.length < size) {
            int n = order.length * 2;
            int[] next = new int[n];
            for (int i = 0; i < order.length; i++) {
                next[i * 2] = order[i];
                next[i * 2 + 1] = n + 1 - order[i];
            }
            order = next;
        }
        return order;
    }

    /** Round one's pairings, as (seed, seed) — slot {@code i} is {@code pairs.get(i)}. */
    static List<int[]> firstRoundPairs(int size) {
        int[] order = seedOrder(size);
        List<int[]> pairs = new ArrayList<>();
        for (int i = 0; i < order.length; i += 2) {
            pairs.add(new int[] {order[i], order[i + 1]});
        }
        return pairs;
    }

    /** How many rounds a bracket of this size plays, up to and including the final. */
    static int rounds(int size) {
        return Integer.numberOfTrailingZeros(size);
    }
}
