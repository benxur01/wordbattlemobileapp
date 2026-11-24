package uz.wordbattle.match;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class BotThinkingDelayTest {

    @Test
    @DisplayName("Pressed bot responds rapidly within 300ms to 600ms")
    void pressedBotDelayIsRapid() {
        for (int i = 0; i < 50; i++) {
            long delay = DuelService.calculateBotThinkingDelayMs(true, 1200, 'A');
            assertThat(delay)
                    .isGreaterThanOrEqualTo(DuelService.PRESSED_BOT_DELAY_MIN_MS)
                    .isLessThan(DuelService.PRESSED_BOT_DELAY_MIN_MS + DuelService.PRESSED_BOT_DELAY_SPREAD_MS);
        }
    }

    @Test
    @DisplayName("Novice bot (<900 rating) exhibits beginner thinking delay between 1800ms and 3000ms")
    void noviceBotDelayPacing() {
        for (int i = 0; i < 50; i++) {
            long delay = DuelService.calculateBotThinkingDelayMs(false, 600, 'S');
            assertThat(delay).isBetween(1800L, 3000L);
        }
    }

    @Test
    @DisplayName("Tactician bot (900..1499 rating) exhibits natural rhythm between 1200ms and 2200ms")
    void tacticianBotDelayPacing() {
        for (int i = 0; i < 50; i++) {
            long delay = DuelService.calculateBotThinkingDelayMs(false, 1200, 'T');
            assertThat(delay).isBetween(1200L, 2200L);
        }
    }

    @Test
    @DisplayName("Master bot (>=1500 rating) exhibits sharp reaction between 800ms and 1500ms")
    void masterBotDelayPacing() {
        for (int i = 0; i < 50; i++) {
            long delay = DuelService.calculateBotThinkingDelayMs(false, 1800, 'M');
            assertThat(delay).isBetween(800L, 1500L);
        }
    }

    @Test
    @DisplayName("Rare letters ('x', 'q', 'z', 'j') add contemplation delay for realistic cognition")
    void rareLettersAddContemplationDelay() {
        char[] rareLetters = {'x', 'X', 'q', 'Q', 'z', 'Z', 'j', 'J'};
        for (char letter : rareLetters) {
            long delay = DuelService.calculateBotThinkingDelayMs(false, 1800, letter);
            // Master base is 800..1500, with rare letter +300..600 bonus => min 1100, max 2100
            assertThat(delay).isBetween(1100L, 2100L);
        }
    }
}
