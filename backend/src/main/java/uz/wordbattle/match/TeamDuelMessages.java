package uz.wordbattle.match;

import java.util.List;
import uz.wordbattle.user.UserDto;

/**
 * Payload shapes the 2v2 duel sends to the client — the four-participant
 * counterpart to {@link DuelMessages}. Frames that mean exactly the same
 * thing regardless of how many people are in the duel, such as
 * {@link DuelMessages.Rejected}, are reused directly rather than redeclared
 * here.
 */
public final class TeamDuelMessages {

    private TeamDuelMessages() {}

    /**
     * One chain entry as a participant sees it: {@code mine} is their own
     * word, {@code ally} their teammate's — anything neither is the opposing
     * team's, the same three-way split {@code DuelState.ChainEntry}'s plain
     * {@code mine}/opponent split makes for two participants instead of four.
     */
    public record TeamChainEntry(String word, long playerId, boolean mine, boolean ally, int spentMs) {}

    public record TeamMatchFound(
            String duelId,
            UserDto partner,
            UserDto opponentOne,
            UserDto opponentTwo,
            /** Always {@code true} for now — see the class note on rating below. */
            boolean rated,
            boolean yourTurn,
            long turnPlayerId,
            String seedWord,
            String needLetter,
            String substitutedFrom,
            int turnSeconds,
            List<TeamChainEntry> chain) {}

    public record TeamDuelState(
            String duelId,
            UserDto partner,
            UserDto opponentOne,
            UserDto opponentTwo,
            List<TeamChainEntry> chain,
            boolean yourTurn,
            long turnPlayerId,
            String needLetter,
            String substitutedFrom,
            int timeLeftMs,
            int turnSeconds,
            int yourWords,
            int partnerWords,
            int opponentOneWords,
            int opponentTwoWords) {}

    public record TeamFinished(
            String duelId,
            String result,
            String reason,
            int delta,
            int ratingBefore,
            int ratingAfter,
            int chainLength,
            int yourWords,
            int averageMs,
            int newWords,
            int streakDays,
            String stuckLetter,
            List<String> hints,
            UserDto partner,
            UserDto opponentOne,
            UserDto opponentTwo) {}
}
