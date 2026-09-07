package uz.wordbattle.match;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.willAnswer;
import static org.mockito.Mockito.mock;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.data.domain.PageRequest;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import uz.wordbattle.config.AppProperties;
import uz.wordbattle.user.User;
import uz.wordbattle.user.UserRepository;
import uz.wordbattle.user.UserService;
import uz.wordbattle.ws.SocketRegistry;

/**
 * What the bot in a duel is rated, which is one number doing two jobs: the
 * opponent the human is shown, and the pool {@code DictionaryService.botMove}
 * answers from.
 *
 * <p>It used to be the literal 400 for everybody. A player who had climbed to
 * 900 was handed a "400" they could not lose to and a player still on their
 * first week met the same one; neither number said anything about the game they
 * were about to play. So a fallback bot now tracks the human it was given to,
 * and a player who asks for one names the strength themselves.
 *
 * <p>Driven through the services with a stand-in socket rather than over a real
 * one: what is being read is the frame that goes out at the start, and there is
 * no wait worth spending 35 seconds of the suite's time on to see it.
 */
@SpringBootTest
class BotDuelRatingTest {

    @Autowired
    private DuelService duels;

    @Autowired
    private MatchmakingService matchmaking;

    @Autowired
    private UserService users;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private MatchRepository matches;

    @Autowired
    private SocketRegistry sockets;

    @Autowired
    private ObjectMapper mapper;

    @Autowired
    private AppProperties props;

    @Test
    void theFallbackBotIsRatedJustAboveThePlayerItWasGivenTo() throws IOException {
        long player = rated("Fallback climber", 528);
        List<JsonNode> frames = connect(player);

        try {
            DuelSession session = duels.startAgainstBot(player);
            assertThat(session).isNotNull();

            int expected = 528 + props.matchmaking().botRatingOffset();
            assertThat(session.botRating()).isEqualTo(expected);
            // The same number on the profile the app draws for the whole duel,
            // which is the part the player actually sees.
            JsonNode opponent = payloadOf(frames, "match.found").path("opponent");
            assertThat(opponent.path("nickname").asText()).isEqualTo("wordbot");
            assertThat(opponent.path("rating").asInt()).isEqualTo(expected);
            assertThat(opponent.path("rating").asInt()).isGreaterThan(528);
        } finally {
            cleanUp(player);
        }
    }

    /** The other player, so it really is tracking rather than a second constant. */
    @Test
    void aStrongerPlayerMeetsAStrongerBot() throws IOException {
        long novice = rated("Bot novice", 400);
        long veteran = rated("Bot veteran", 1350);
        List<JsonNode> noviceFrames = connect(novice);
        List<JsonNode> veteranFrames = connect(veteran);

        try {
            duels.startAgainstBot(novice);
            duels.startAgainstBot(veteran);

            int forNovice = payloadOf(noviceFrames, "match.found").path("opponent").path("rating").asInt();
            int forVeteran = payloadOf(veteranFrames, "match.found").path("opponent").path("rating").asInt();
            assertThat(forVeteran).isGreaterThan(forNovice);
        } finally {
            cleanUp(novice);
            cleanUp(veteran);
        }
    }

    @Test
    void aPlayerWhoPicksTheStrengthGetsExactlyThatBot() throws IOException {
        long player = rated("Bot picker", 700);
        List<JsonNode> frames = connect(player);

        try {
            DuelSession session = duels.startAgainstChosenBot(player, 1400, null);
            assertThat(session).isNotNull();

            assertThat(session.botRating()).isEqualTo(1400);
            assertThat(payloadOf(frames, "match.found").path("opponent").path("rating").asInt()).isEqualTo(1400);
        } finally {
            cleanUp(player);
        }
    }

    /**
     * The chosen rating arrives from a client, so it is clamped rather than
     * believed — a 9,000,000 would otherwise be written to the match row and
     * shown as the opponent's rating for the whole duel.
     */
    @Test
    void aRatingOutsideThePickersRangeIsClampedToIt() throws IOException {
        long player = rated("Bot cheater", 700);
        connect(player);

        try {
            assertThat(duels.startAgainstChosenBot(player, 9_000_000, null).botRating())
                    .isEqualTo(DuelService.MAX_BOT_RATING);
            cleanUp(player);

            assertThat(duels.startAgainstChosenBot(player, -5000, null).botRating())
                    .isEqualTo(DuelService.MIN_BOT_RATING);
        } finally {
            cleanUp(player);
        }
    }

    /** The same clamp through the frame the app actually sends. */
    @Test
    void theBotFrameClampsWhateverTheClientAsksFor() throws IOException {
        long player = rated("Bot frame sender", 700);
        List<JsonNode> frames = connect(player);

        try {
            matchmaking.joinAgainstBot(player, 9_000_000, null);

            assertThat(duels.isPlaying(player)).isTrue();
            assertThat(payloadOf(frames, "match.found").path("opponent").path("rating").asInt())
                    .isEqualTo((int) DuelService.MAX_BOT_RATING);

            // And a player already in a duel is told so rather than being given
            // a second one — the same refusal joining the queue gets.
            matchmaking.joinAgainstBot(player, 800, null);
            assertThat(payloadOf(frames, "error").path("code").asText()).isEqualTo("already_in_duel");
        } finally {
            cleanUp(player);
        }
    }

    /**
     * What the history card is drawn from once the duel is over. The bot has no
     * row of its own, so the rating it played at is written onto the match or it
     * is lost — and the card would be back to claiming 400 for every bot duel
     * ever played.
     *
     * <p>The human's own rating is checked as well, and that assertion is not
     * incidental: every route into a bot duel has to stay unrated, however the
     * bot was rated, or picking a weak one would be a way to farm the ladder.
     */
    @Test
    void aBotDuelIsRecordedUnratedAtTheRatingItWasPlayedAt() throws IOException {
        long player = rated("Bot historian", 640);
        connect(player);

        try {
            assertThat(duels.startAgainstChosenBot(player, 1200, null)).isNotNull();
            // Forfeiting is the quickest end there is, and waiting for the
            // settlement is the only way to read the row it writes.
            duels.forfeitAndAwaitSettlement(player);

            List<MatchEntity> history = matches.findHistory(player, PageRequest.of(0, 1));
            assertThat(history).hasSize(1);
            assertThat(history.get(0).isBotOpponent()).isTrue();
            assertThat(history.get(0).getPlayerTwoRatingBefore()).isEqualTo(1200);

            assertThat(userRepository.findById(player).orElseThrow().getRating())
                    .as("a bot duel settles no rating, whatever the bot was rated")
                    .isEqualTo(640);
        } finally {
            cleanUp(player);
        }
    }

    // --------------------------------------------------------------- helpers

    /** A fresh account moved off the 400 every one of them starts on. */
    private long rated(String displayName, double rating) {
        User user = users.createDevUser(displayName);
        user.setRating(rating);
        return userRepository.save(user).getId();
    }

    private void cleanUp(long playerId) {
        duels.forfeit(playerId);
        sockets.disconnect(playerId);
    }

    /**
     * A stand-in socket that keeps what was written to it — the same one
     * {@code BannedPlayerCannotDuelTest} uses, and for the same reason: a duel
     * only announces itself to a connected player, and a real client here would
     * buy nothing but a handshake.
     */
    private List<JsonNode> connect(long userId) throws IOException {
        List<JsonNode> frames = new ArrayList<>();
        WebSocketSession socket = mock(WebSocketSession.class);
        given(socket.isOpen()).willReturn(true);
        given(socket.getId()).willReturn("socket-" + userId);
        willAnswer(invocation -> {
            TextMessage message = invocation.getArgument(0);
            synchronized (frames) {
                frames.add(mapper.readTree(message.getPayload()));
            }
            return null;
        })
                .given(socket)
                .sendMessage(any());
        sockets.register(userId, socket);
        return frames;
    }

    /** The payload of the last frame of this type the socket was sent. */
    private JsonNode payloadOf(List<JsonNode> frames, String type) {
        synchronized (frames) {
            return frames.stream()
                    .filter(frame -> type.equals(frame.path("type").asText()))
                    .reduce((first, second) -> second)
                    .orElseThrow(() -> new AssertionError("No '" + type + "' frame was sent"))
                    .path("payload");
        }
    }
}
