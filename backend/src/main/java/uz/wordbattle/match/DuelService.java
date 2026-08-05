package uz.wordbattle.match;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Random;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import jakarta.annotation.PreDestroy;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import uz.wordbattle.config.AppProperties;
import uz.wordbattle.dictionary.DictionaryService;
import uz.wordbattle.friend.PresenceService;
import uz.wordbattle.match.DuelMessages.ChainEntry;
import uz.wordbattle.match.MatchEntity.EndReason;
import uz.wordbattle.user.User;
import uz.wordbattle.user.UserDto;
import uz.wordbattle.user.UserService;
import uz.wordbattle.ws.SocketRegistry;

/**
 * Runs live duels: turn timers, word validation, bot replies and the finish
 * bookkeeping (rating, stats, persistence).
 *
 * <p>All rules are enforced here rather than in the app. A tampered client can
 * send anything it likes; the worst it achieves is a rejection.
 */
@Service
public class DuelService {

    private static final Logger log = LoggerFactory.getLogger(DuelService.class);

    /** Words the chain can open with — always common, always 5+ letters. */
    private static final List<String> SEED_WORDS =
            List.of("battle", "silver", "planet", "candle", "forest", "market", "window", "garden");

    private final Map<String, DuelSession> duels = new ConcurrentHashMap<>();
    private final Map<Long, String> duelByPlayer = new ConcurrentHashMap<>();

    private final ScheduledExecutorService scheduler = Executors.newScheduledThreadPool(2, runnable -> {
        Thread thread = new Thread(runnable, "duel-timer");
        thread.setDaemon(true);
        return thread;
    });
    private final Random random = new Random();

    private final AppProperties props;
    private final DictionaryService dictionary;
    private final SocketRegistry sockets;
    private final UserService users;
    private final PresenceService presence;
    private final MatchResultService results;

    public DuelService(
            AppProperties props,
            DictionaryService dictionary,
            SocketRegistry sockets,
            UserService users,
            PresenceService presence,
            MatchResultService results) {
        this.props = props;
        this.dictionary = dictionary;
        this.sockets = sockets;
        this.users = users;
        this.presence = presence;
        this.results = results;
    }

    @PreDestroy
    void shutdown() {
        scheduler.shutdownNow();
    }

    // ---------------------------------------------------------------- start

    /** Starts a human-vs-human duel and tells both sides. */
    public DuelSession start(long playerOne, long playerTwo) {
        return start(playerOne, playerTwo, false);
    }

    /** Starts a duel against the bot (unrated). */
    public DuelSession startAgainstBot(long player) {
        return start(player, DuelSession.BOT_ID, true);
    }

    private DuelSession start(long playerOne, long playerTwo, boolean bot) {
        String seed = SEED_WORDS.get(random.nextInt(SEED_WORDS.size()));
        DuelSession session = new DuelSession(UUID.randomUUID().toString(), playerOne, playerTwo, bot, seed);

        duels.put(session.id(), session);
        duelByPlayer.put(playerOne, session.id());
        presence.battleStarted(playerOne);
        if (!bot) {
            duelByPlayer.put(playerTwo, session.id());
            presence.battleStarted(playerTwo);
        }

        announce(session, playerOne);
        if (!bot) announce(session, playerTwo);

        armTurnTimer(session);
        log.info("Duel {} started: {} vs {}{}", session.id(), playerOne, playerTwo, bot ? " (bot)" : "");
        return session;
    }

    private void announce(DuelSession session, long playerId) {
        long opponentId = session.opponentOf(playerId);
        UserDto opponent = opponentId == DuelSession.BOT_ID
                ? botProfile()
                : UserDto.of(users.require(opponentId));

        sockets.send(playerId, "match.found", new DuelMessages.MatchFound(
                session.id(),
                opponent,
                !session.botOpponent(),
                session.turn() == playerId,
                session.chain().get(0).word(),
                String.valueOf(session.requiredLetter()),
                props.duel().turnSeconds(),
                chainFor(session, playerId)));
    }

    private UserDto botProfile() {
        return new UserDto(DuelSession.BOT_ID, "wordbot", "Word Bot", "W", null, 1200, 0);
    }

    // --------------------------------------------------------------- moves

    /** A player's word. Invalid words are rejected without losing the turn. */
    public void submit(long playerId, String rawWord) {
        DuelSession session = duelOf(playerId).orElse(null);
        if (session == null || session.finished()) {
            sockets.sendError(playerId, "no_duel", "Faol jang topilmadi");
            return;
        }
        synchronized (session) {
            if (session.finished()) return;
            if (session.turn() != playerId) {
                reject(playerId, "not_your_turn", "Hozir raqibning navbati");
                return;
            }

            String word = rawWord == null ? "" : rawWord.trim().toLowerCase();
            String problem = validate(session, word);
            if (problem != null) {
                reject(playerId, problem, messageFor(problem, session));
                return;
            }

            int spentMs = (int) Duration.between(session.turnStartedAt(), Instant.now()).toMillis();
            session.addWord(word, playerId, spentMs);

            // Reaching the target number of words wins the duel outright.
            if (session.wordsBy(playerId) >= props.duel().wordsToWin()) {
                finish(session, playerId, EndReason.WORDS_LIMIT);
                return;
            }

            long opponent = session.opponentOf(playerId);
            session.passTurnTo(opponent);
            broadcastState(session);
            armTurnTimer(session);

            if (session.botOpponent()) scheduleBotMove(session);
        }
    }

    /** Quitting, backing out of the duel screen, or losing the connection. */
    public void forfeit(long playerId) {
        duelOf(playerId).ifPresent(session -> {
            synchronized (session) {
                if (session.finished()) return;
                finish(session, session.opponentOf(playerId), EndReason.FORFEIT);
            }
        });
    }

    private String validate(DuelSession session, String word) {
        if (word.isEmpty()) return "empty";
        if (!word.chars().allMatch(c -> c >= 'a' && c <= 'z')) return "letters_only";
        if (word.length() < props.duel().minWordLength()) return "too_short";
        if (word.charAt(0) != session.requiredLetter()) return "wrong_letter";
        if (session.alreadyUsed(word)) return "already_used";
        if (!dictionary.isValid(word)) return "not_a_word";
        return null;
    }

    private String messageFor(String code, DuelSession session) {
        return switch (code) {
            case "letters_only" -> "Faqat ingliz harflari";
            case "too_short" -> "Kamida " + props.duel().minWordLength() + " ta harf";
            case "wrong_letter" -> "«" + Character.toUpperCase(session.requiredLetter()) + "» harfi bilan boshlanishi kerak";
            case "already_used" -> "Bu so'z zanjirda bor";
            case "not_a_word" -> "Bu so'z ingliz lug'atida yo'q";
            case "not_your_turn" -> "Hozir raqibning navbati";
            default -> "So'z qabul qilinmadi";
        };
    }

    private void reject(long playerId, String code, String message) {
        sockets.send(playerId, "duel.rejected", new DuelMessages.Rejected(code, message));
    }

    // --------------------------------------------------------------- timers

    private void armTurnTimer(DuelSession session) {
        long millis = props.duel().turnSeconds() * 1000L;
        session.setTurnTimer(scheduler.schedule(() -> onTurnExpired(session), millis, TimeUnit.MILLISECONDS));
    }

    private void onTurnExpired(DuelSession session) {
        synchronized (session) {
            if (session.finished()) return;
            long loser = session.turn();
            finish(session, session.opponentOf(loser), EndReason.TIMEOUT);
        }
    }

    private void scheduleBotMove(DuelSession session) {
        long delay = 1200 + random.nextInt(1200);
        scheduler.schedule(() -> playBotMove(session), delay, TimeUnit.MILLISECONDS);
    }

    private void playBotMove(DuelSession session) {
        synchronized (session) {
            if (session.finished() || session.turn() != DuelSession.BOT_ID) return;

            String word = dictionary.botMove(
                    session.requiredLetter(), session.used(), props.duel().minWordLength() + 1);
            if (word == null) {
                // The bot is stuck: the human wins.
                finish(session, session.playerOne(), EndReason.NO_MOVES);
                return;
            }

            int spentMs = (int) Duration.between(session.turnStartedAt(), Instant.now()).toMillis();
            session.addWord(word, DuelSession.BOT_ID, spentMs);
            session.passTurnTo(session.playerOne());
            broadcastState(session);
            armTurnTimer(session);
        }
    }

    // -------------------------------------------------------------- finish

    private void finish(DuelSession session, long winnerId, EndReason reason) {
        if (!session.finish()) return;

        duels.remove(session.id());
        duelByPlayer.remove(session.playerOne());
        presence.battleEnded(session.playerOne());
        if (!session.botOpponent()) {
            duelByPlayer.remove(session.playerTwo());
            presence.battleEnded(session.playerTwo());
        }

        MatchResultService.Outcome outcome = results.record(session, winnerId, reason);

        notifyFinish(session, session.playerOne(), winnerId, reason, outcome);
        if (!session.botOpponent()) {
            notifyFinish(session, session.playerTwo(), winnerId, reason, outcome);
        }
        log.info("Duel {} finished: winner={} reason={}", session.id(), winnerId, reason);
    }

    private void notifyFinish(
            DuelSession session, long playerId, long winnerId, EndReason reason, MatchResultService.Outcome outcome) {

        MatchResultService.PlayerResult result = outcome.forPlayer(playerId);
        boolean won = winnerId == playerId;

        // The lose screen offers three words for the letter the player got
        // stuck on, so the hint is only computed for the loser.
        String stuckLetter = null;
        List<String> hints = List.of();
        if (!won) {
            char letter = session.requiredLetter();
            stuckLetter = String.valueOf(Character.toUpperCase(letter));
            hints = dictionary.hints(letter, session.used(), 3);
        }

        sockets.send(playerId, "duel.finished", new DuelMessages.Finished(
                session.id(),
                won ? "win" : "lose",
                reason.name().toLowerCase(),
                !session.botOpponent(),
                result.delta(),
                result.ratingBefore(),
                result.ratingAfter(),
                session.chainLength(),
                session.wordsBy(playerId),
                session.averageMsOf(playerId),
                result.newWords(),
                result.streakDays(),
                stuckLetter,
                hints));
    }

    // ---------------------------------------------------------------- state

    private void broadcastState(DuelSession session) {
        sendState(session, session.playerOne());
        if (!session.botOpponent()) sendState(session, session.playerTwo());
    }

    public void sendState(DuelSession session, long playerId) {
        int elapsed = (int) Duration.between(session.turnStartedAt(), Instant.now()).toMillis();
        int timeLeft = Math.max(0, props.duel().turnSeconds() * 1000 - elapsed);
        long opponent = session.opponentOf(playerId);

        sockets.send(playerId, "duel.update", new DuelMessages.DuelState(
                session.id(),
                chainFor(session, playerId),
                session.turn() == playerId,
                String.valueOf(session.requiredLetter()),
                timeLeft,
                props.duel().turnSeconds(),
                session.wordsBy(playerId),
                session.wordsBy(opponent),
                session.turn() != playerId));
    }

    private List<ChainEntry> chainFor(DuelSession session, long playerId) {
        List<ChainEntry> out = new ArrayList<>();
        for (DuelSession.ChainWord word : session.chain()) {
            out.add(new ChainEntry(word.word(), word.playerId() == playerId, word.spentMs()));
        }
        return out;
    }

    public Optional<DuelSession> duelOf(long playerId) {
        String id = duelByPlayer.get(playerId);
        return id == null ? Optional.empty() : Optional.ofNullable(duels.get(id));
    }

    public boolean isPlaying(long playerId) {
        return duelOf(playerId).isPresent();
    }

    public int activeDuels() {
        return duels.size();
    }

    /** Words in this duel that the player had never played before. */
    Set<String> wordsPlayedBy(DuelSession session, long playerId) {
        Set<String> out = new HashSet<>();
        for (DuelSession.ChainWord word : session.chain()) {
            if (word.playerId() == playerId) out.add(word.word());
        }
        return out;
    }

    User requireUser(long id) {
        return users.require(id);
    }
}
