package uz.wordbattle.match;

/**
 * The four helps a player may call on, once each, in a duel against the bot.
 *
 * <p>Bot practice only, and deliberately so: every one of them bends a rule the
 * rated game is built on — the turn's length, the letter the chain hands over,
 * knowing a word without having thought of it. A practice duel moves no rating
 * and has nobody on the other side to be treated unfairly, which is what makes
 * them harmless there and impossible anywhere else. {@code DuelService.usePowerUp}
 * is where that is enforced.
 *
 * <p>{@link #id()} is what the frames carry, so the app and the server name the
 * same thing without either having to know the other's spelling of it.
 */
public enum PowerUp {

    /** Adds {@code DuelService.ADD_TIME_MS} to the turn the player is on. */
    ADD_TIME("add_time"),

    /** Turns down the letter the chain is asking for; the next one takes its place. */
    SKIP_LETTER("skip_letter"),

    /** A few words that would answer the current letter. Changes nothing. */
    HINT("hint"),

    /** Makes the bot answer the next move at once instead of taking its time. */
    PRESSURE("pressure");

    private final String id;

    PowerUp(String id) {
        this.id = id;
    }

    public String id() {
        return id;
    }

    /** The power-up a frame asked for, or null when it named none of them. */
    public static PowerUp of(String id) {
        for (PowerUp powerUp : values()) {
            if (powerUp.id.equals(id)) return powerUp;
        }
        return null;
    }
}
