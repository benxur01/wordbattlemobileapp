package uz.wordbattle.match;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.then;
import static org.mockito.BDDMockito.willThrow;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.mock;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.util.Map;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import uz.wordbattle.user.UserService;
import uz.wordbattle.ws.SocketRegistry;

/**
 * The finish frame written to a socket that died on the way.
 *
 * <p>A duel's result is the one frame a player is owed rather than merely sent:
 * their rating has already moved by the time it goes out, and the app sits on a
 * live board until it arrives. That is why a player who is plainly offline has
 * their result shelved for the reconnect — but the player who merely *looked*
 * reachable had no such net. The settlement asked the registry, was told yes,
 * and wrote; and a write to a session that has closed since is a silent no-op,
 * while one that fails outright is swallowed at DEBUG. Either way the send said
 * nothing, so nothing was shelved, and the reconnect that followed found an
 * empty shelf and put the player back on the lobby with a rating that had moved
 * for a duel they were never told the end of.
 *
 * <p>The gap between the lookup and the write is microseconds wide, so it is
 * reproduced rather than raced for: the socket here answers every question as
 * open and refuses every write, which is precisely what the server saw. Nothing
 * about the duel is mocked — it is started, forfeited and settled for real.
 *
 * <p>{@link MissedFinishRaceTest} is the neighbouring case, where the player was
 * already gone and the shelving itself lost a race with their return.
 */
@SpringBootTest
class DroppedFinishFrameTest {

    @Autowired
    private DuelService duels;

    @Autowired
    private UserService users;

    @Autowired
    private SocketRegistry sockets;

    @Autowired
    private ObjectMapper mapper;

    /** The player whose socket refuses the result. A field so it can be cleaned up. */
    private long winner;

    /**
     * The registry is one bean for the whole context, so a stand-in socket left
     * behind would go on counting as somebody online for every test after this
     * one — however this one ended.
     */
    @AfterEach
    void tearDown() {
        if (winner != 0) sockets.disconnect(winner);
    }

    @Test
    void aResultTheSocketRefusedIsKeptForTheReconnectRatherThanLost() throws Exception {
        winner = users.createDevUser("Told nothing").getId();
        long quitter = users.createDevUser("Walked out").getId();

        // Open to every question, closed to every write: a socket in the state
        // this bug lives in.
        WebSocketSession dying = mock(WebSocketSession.class);
        given(dying.getId()).willReturn("dying");
        given(dying.isOpen()).willReturn(true);
        willThrow(new IOException("broken pipe")).given(dying).sendMessage(any(TextMessage.class));
        sockets.register(winner, dying);

        assertThat(duels.start(winner, quitter)).isNotNull();
        // The duel really settles: the wait is the settlement's own, so the
        // frame has been written — or dropped — by the time this returns.
        duels.forfeitAndAwaitSettlement(quitter);

        // The player comes back on a socket that works, exactly as the app does
        // after a drop, and asks for whatever was left for them.
        WebSocketSession reconnected = mock(WebSocketSession.class);
        given(reconnected.getId()).willReturn("reconnected");
        given(reconnected.isOpen()).willReturn(true);
        sockets.register(winner, reconnected);
        duels.sendMissedFinish(winner);

        // Their result is there. Without the send reporting its failure, the
        // frame was never shelved at all and this reconnect is handed nothing —
        // for good, since a duel is only ever asked after once.
        assertThat(finishFrameSentTo(reconnected))
                .as("the result of a duel whose finish frame the socket refused")
                .containsEntry("result", "win")
                .containsEntry("reason", "forfeit");
    }

    /** The {@code duel.finished} payload this session was written, as a map. */
    private Map<String, Object> finishFrameSentTo(WebSocketSession session) throws Exception {
        ArgumentCaptor<TextMessage> written = ArgumentCaptor.forClass(TextMessage.class);
        then(session).should(atLeastOnce()).sendMessage(written.capture());
        for (TextMessage message : written.getAllValues()) {
            JsonNode frame = mapper.readTree(message.getPayload());
            if ("duel.finished".equals(frame.path("type").asText())) {
                return mapper.convertValue(frame.path("payload"), new TypeReference<>() {});
            }
        }
        throw new AssertionError("No 'duel.finished' frame reached the socket: " + written.getAllValues());
    }
}
