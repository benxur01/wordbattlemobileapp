package uz.wordbattle.dictionary;

/**
 * A topic a duel can be restricted to: both sides then play inside one word
 * list instead of the whole dictionary.
 *
 * <p>The name is the one the player is shown, in Uzbek like every other string
 * this server sends a screen, and the id is what the {@code queue.bot} frame
 * carries. Only bot practice offers this — see {@code MatchmakingService} — so
 * nothing here has to survive being matched against another player's choice.
 *
 * <p>The set is fixed rather than configurable because each entry is a file
 * that ships with the server: a theme nobody wrote a word list for would be an
 * id the picker offers and the duel cannot start.
 */
public enum WordTheme {
    ANIMALS("animals", "Hayvonlar"),
    FOOD("food", "Ovqat"),
    NATURE("nature", "Tabiat"),
    SPORTS("sports", "Sport"),
    TECHNOLOGY("technology", "Texnologiya"),
    TRAVEL("travel", "Sayohat"),
    BODY("body", "Tana va sog'liq"),
    JOBS("jobs", "Kasblar");

    private final String id;
    private final String label;

    WordTheme(String id, String label) {
        this.id = id;
        this.label = label;
    }

    public String id() {
        return id;
    }

    public String label() {
        return label;
    }

    String resource() {
        return "words/theme-" + id + "-en.txt";
    }

    /** The theme an id names, or null for one no build of this server knows. */
    public static WordTheme of(String id) {
        for (WordTheme theme : values()) {
            if (theme.id.equals(id)) return theme;
        }
        return null;
    }
}
