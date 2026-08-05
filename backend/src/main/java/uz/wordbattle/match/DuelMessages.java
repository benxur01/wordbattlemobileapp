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
            int turnSeconds,
            List<ChainEntry> chain) {}

    public record DuelState(
            String duelId,
            List<ChainEntry> chain,
            boolean yourTurn,
            String needLetter,
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
