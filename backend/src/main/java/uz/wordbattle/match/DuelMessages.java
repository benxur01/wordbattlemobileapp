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
