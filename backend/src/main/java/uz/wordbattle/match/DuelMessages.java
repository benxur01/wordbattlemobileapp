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
            /** The theme's name, or null for a duel played against the whole dictionary. */
            String theme,
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
            /**
             * The theme this duel is restricted to, named for the screen to
             * show — null, and so absent from the frame, for the ordinary
             * whole-dictionary duel. Repeated on every state frame for the
             * same reason the two fields above it are: the player whose app
             * was relaunched mid-duel is never sent {@link MatchFound} again,
             * and a themed board that stopped saying so would leave them
             * reading perfectly good words being refused.
             */
            String theme,
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
            /**
             * Why that letter was stepped over: {@code rare_letter} for the
             * game's own rule, {@code power_up} for a player who spent their
             * skip on it. Null exactly when {@code substitutedFrom} is, and only
             * ever {@code power_up} in a duel against the bot — the only place
             * {@link PowerUp} exists at all.
             */
            String substitutionReason,
            int timeLeftMs,
            int turnSeconds,
            int yourWords,
            int opponentWords,
            boolean opponentThinking) {}

    public record Rejected(String code, String message) {}

    /**
     * A power-up the server has just spent, so the app can grey the button out
     * — the charge is the server's to give, and a client that marked its own
     * would lose one to every refusal.
     *
     * <p>What the power-up actually did arrives in the state frame it triggers
     * (a longer clock, a new letter) rather than here. {@code words} is the
     * exception, being the whole of {@link PowerUp#HINT}: it changes nothing
     * about the duel and has nowhere else to go. Empty for the other three.
     */
    public record PowerUpUsed(String type, List<String> words) {}

    public record SpectateChainEntry(String word, long playerId, int spentMs) {}

    /**
     * A duel's state as a third party sees it: both players named outright,
     * rather than the {@code mine}/{@code opponent} shape {@link DuelState}
     * uses for the two people actually playing.
     */
    public record SpectateState(
            String duelId,
            UserDto playerOne,
            UserDto playerTwo,
            List<SpectateChainEntry> chain,
            long turnPlayerId,
            String needLetter,
            String substitutedFrom,
            int timeLeftMs,
            int turnSeconds,
            int playerOneWords,
            int playerTwoWords) {}

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
