package uz.wordbattle.match;

import java.util.List;
import uz.wordbattle.user.UserDto;

/** Payload shapes the duel sends to the client. */
public final class DuelMessages {

    private DuelMessages() {}

    public record ChainEntry(String word, boolean mine, int spentMs) {}

    public record MatchFound(
            String duelId,
            UserDto opponent,
            boolean rated,
            boolean yourTurn,
            String seedWord,
            String needLetter,
            String substitutedFrom,
            int turnSeconds,
            List<ChainEntry> chain) {}

    public record DuelState(
            String duelId,
            /**
             * Who the player is up against, and whether the duel moves anyone's
             * rating. Neither changes for the life of a duel, and both are also
             * in {@link MatchFound} — but a player whose app was killed and
             * relaunched mid-battle never saw that frame and never will, and
             * this one is the only thing the server sends them. Without these
             * two the app could not build a board out of it, so it threw the
             * frame away and left them on the lobby while their turn timer ran
             * out and charged them a rated loss they were never shown.
             *
             * <p>Repeating them on every move costs a name and a boolean; the
             * cheaper-looking alternative, sending them only on the reconnect
             * frame, is how the app came to depend on {@code match.found} in
             * the first place.
             */
            UserDto opponent,
            boolean rated,
            List<ChainEntry> chain,
            boolean yourTurn,
            String needLetter,
            /**
             * The rare letter {@code needLetter} was substituted for, or null
             * on the turns nothing was substituted — and null fields are left
             * out of the frame entirely, so the client sees the note appear and
             * disappear with the chain rather than having to track it.
             */
            String substitutedFrom,
            int timeLeftMs,
            int turnSeconds,
            int yourWords,
            int opponentWords,
            boolean opponentThinking) {}

    public record Rejected(String code, String message) {}

    public record Finished(
            String duelId,
            long opponentId,
            boolean opponentIsBot,
            String result,
            String reason,
            boolean rated,
            int delta,
            int ratingBefore,
            int ratingAfter,
            int chainLength,
            int yourWords,
            int averageMs,
            int newWords,
            int streakDays,
            String stuckLetter,
            List<String> hints) {}
}
