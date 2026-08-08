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
import java.util.concurrent.ScheduledFuture;
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

    /**
     * How long a player may be off the socket before the duel is handed to
     * their opponent. The app reconnects on its own after 1s, then 2s, 4s, 8s,
     * 15s — so it is back by the 1s, 3s or 7s mark unless the network really is
     * gone, and ten seconds covers all three of those attempts. A WiFi-to-
     * cellular handoff, a lift or a locked screen therefore costs nothing,
     * while somebody who actually walked away still loses in about the time the
     * turn timer would have taken care of them anyway.
     *
     * <p>Package-private: the socket tests time themselves off it.
     */
    static final long DISCONNECT_GRACE_SECONDS = 10;

    /**
     * How long the result of a duel that ended while the player was away is
     * kept for them: long enough for the reconnect backoff to run its course,
     * short enough that somebody returning much later is not dragged onto the
     * result screen of a duel they have long forgotten.
     */
    private static final Duration MISSED_FINISH_TTL = Duration.ofMinutes(2);

    /** A finish frame its owner was offline to receive. */
    private record MissedFinish(DuelMessages.Finished frame, Instant at) {}

    private final Map<String, DuelSession> duels = new ConcurrentHashMap<>();
    private final Map<Long, String> duelByPlayer = new ConcurrentHashMap<>();
    private final Map<Long, ScheduledFuture<?>> pendingForfeits = new ConcurrentHashMap<>();
    private final Map<Long, MissedFinish> missedFinishes = new ConcurrentHashMap<>();

    /**
     * Turn timers, bot moves and the settlement of finished duels all run here.
     * Two threads used to serve every concurrent duel on the server, so one
     * slow finish (a database transaction) delayed unrelated turn timers; the
     * pool now scales with the machine and never drops below four.
     */
    private final ScheduledExecutorService scheduler = Executors.newScheduledThreadPool(
            Math.max(4, Runtime.getRuntime().availableProcessors()), runnable -> {
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

    /**
     * A restart used to leave every live duel unfinished: no result was written
     * and no player was told anything, so both sides sat on a duel screen until
     * they gave up. Shutting down now ends them the only fair way — nobody
     * wins, no rating moves — and lets the queued settlements drain before the
     * pool closes.
     */
    @PreDestroy
    void shutdown() {
        for (DuelSession session : List.copyOf(duels.values())) {
            synchronized (session) {
                if (!session.finished()) abort(session);
            }
        }
        scheduler.shutdown();
        try {
            if (!scheduler.awaitTermination(5, TimeUnit.SECONDS)) scheduler.shutdownNow();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            scheduler.shutdownNow();
        }
    }

    // ---------------------------------------------------------------- start

    /** Starts a human-vs-human duel and tells both sides. Null if either is busy. */
    public DuelSession start(long playerOne, long playerTwo) {
        return start(playerOne, playerTwo, false);
    }

    /** Starts a duel against the bot (unrated). */
    public DuelSession startAgainstBot(long player) {
        return start(player, DuelSession.BOT_ID, true);
    }

    /**
     * Refuses rather than starting a second duel for someone already playing.
     * Callers check first; this is the backstop for the race between an invite
     * being accepted and the same player being paired by matchmaking. Two live
     * duels for one player corrupts both, because a player maps to exactly one
     * duel and whichever ends first would clear the other's registration.
     */
    private DuelSession start(long playerOne, long playerTwo, boolean bot) {
        if (isPlaying(playerOne) || (!bot && isPlaying(playerTwo))) {
            log.warn("Refusing duel {} vs {}: already playing", playerOne, playerTwo);
            return null;
        }
        String seed = SEED_WORDS.get(random.nextInt(SEED_WORDS.size()));
        DuelSession session = new DuelSession(UUID.randomUUID().toString(), playerOne, playerTwo, bot, seed);

        duels.put(session.id(), session);
        duelByPlayer.put(playerOne, session.id());
        presence.battleStarted(playerOne);
        // A new duel supersedes any result still waiting to be collected.
        missedFinishes.remove(playerOne);
        if (!bot) {
            duelByPlayer.put(playerTwo, session.id());
            presence.battleStarted(playerTwo);
            missedFinishes.remove(playerTwo);
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
        // Checked before the character scan so a client cannot make the server
        // walk a megabyte of text per frame.
        if (word.length() > props.limits().maxWordLength()) return "too_long";
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
            case "too_long" -> "Bunday uzun so'z yo'q";
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

    // ---------------------------------------------------------- disconnects

    /**
     * The player's socket dropped. Losing the connection still hands the win to
     * the opponent — otherwise pulling the plug would be a free escape — but a
     * phone drops its socket for all sorts of innocent reasons, so the forfeit
     * waits out {@link #DISCONNECT_GRACE_SECONDS} and only lands if the player
     * has not come back by then.
     */
    public void connectionLost(long playerId) {
        if (duelOf(playerId).isEmpty()) return;
        ScheduledFuture<?> previous = pendingForfeits.put(
                playerId,
                scheduler.schedule(() -> forfeitIfStillAway(playerId), DISCONNECT_GRACE_SECONDS, TimeUnit.SECONDS));
        if (previous != null) previous.cancel(false);
    }

    /** The player is back on a socket: call off any forfeit waiting on them. */
    public void connectionRestored(long playerId) {
        ScheduledFuture<?> pending = pendingForfeits.remove(playerId);
        if (pending != null) pending.cancel(false);
    }

    private void forfeitIfStillAway(long playerId) {
        // Always drop the entry, including for players who never come back:
        // the task has run and nothing else will clean up after it.
        pendingForfeits.remove(playerId);
        // The window can run out a hair after the new socket turned up.
        if (sockets.isConnected(playerId)) return;
        log.info("Player {} stayed away for {}s, forfeiting", playerId, DISCONNECT_GRACE_SECONDS);
        forfeit(playerId);
    }

    /**
     * Hands a returning player the result of the duel that ended while they
     * were disconnected. Without it they come back to a duel screen that will
     * never move again, because the finish frame was written to a dead socket.
     */
    public void sendMissedFinish(long playerId) {
        MissedFinish missed = missedFinishes.remove(playerId);
        if (missed == null || missed.at().isBefore(Instant.now().minus(MISSED_FINISH_TTL))) return;
        sockets.send(playerId, "duel.finished", missed.frame());
    }

    private void rememberMissedFinish(long playerId, DuelMessages.Finished frame) {
        Instant now = Instant.now();
        // Players who never return never collect theirs, so anything past its
        // shelf life is swept here rather than left to pile up.
        missedFinishes.values().removeIf(missed -> missed.at().isBefore(now.minus(MISSED_FINISH_TTL)));
        missedFinishes.put(playerId, new MissedFinish(frame, now));
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
        deregister(session);

        // Recording a result is a database transaction, and every caller of
        // finish() holds this duel's monitor. Settling on the pool instead
        // keeps that monitor — and the timer thread that took it — free.
        scheduler.execute(() -> settle(session, winnerId, reason));
    }

    private void settle(DuelSession session, long winnerId, EndReason reason) {
        try {
            MatchResultService.Outcome outcome = results.record(session, winnerId, reason);
            notifyFinish(session, session.playerOne(), winnerId, reason, outcome);
            if (!session.botOpponent()) {
                notifyFinish(session, session.playerTwo(), winnerId, reason, outcome);
            }
            log.info("Duel {} finished: winner={} reason={}", session.id(), winnerId, reason);
        } catch (RuntimeException e) {
            log.error("Duel {} could not be settled", session.id(), e);
        }
    }

    /**
     * Ends a duel nobody won — used when the server itself is going away. No
     * result is recorded and no rating moves; the players are simply told the
     * duel is over so their screens can move on.
     */
    private void abort(DuelSession session) {
        if (!session.finish()) return;
        deregister(session);
        for (long playerId : session.botOpponent()
                ? new long[] {session.playerOne()}
                : new long[] {session.playerOne(), session.playerTwo()}) {
            sockets.send(playerId, "duel.aborted", Map.of(
                    "duelId", session.id(),
                    "message", "Server qayta ishga tushmoqda — jang bekor qilindi"));
        }
        log.info("Duel {} aborted (shutdown)", session.id());
    }

    /**
     * Takes the duel out of the live registries. Both removals are conditional
     * on the entry still belonging to <em>this</em> session: an unconditional
     * remove would tear down whatever duel the player had moved on to.
     */
    private void deregister(DuelSession session) {
        duels.remove(session.id(), session);
        if (duelByPlayer.remove(session.playerOne(), session.id())) {
            presence.battleEnded(session.playerOne());
        }
        if (!session.botOpponent() && duelByPlayer.remove(session.playerTwo(), session.id())) {
            presence.battleEnded(session.playerTwo());
        }
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

        DuelMessages.Finished frame = new DuelMessages.Finished(
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
                hints);

        // A player who lost the socket — the usual way a duel ends this way —
        // cannot be told now, so the result is kept for their reconnect.
        if (sockets.isConnected(playerId)) {
            sockets.send(playerId, "duel.finished", frame);
        } else {
            rememberMissedFinish(playerId, frame);
        }
    }

    // ---------------------------------------------------------------- state

    private void broadcastState(DuelSession session) {
        sendState(session, session.playerOne());
        if (!session.botOpponent()) sendState(session, session.playerTwo());
    }

    /**
     * Callable from any thread — a reconnect arrives on a socket thread while a
     * bot move may be appending to the chain on a timer thread. Reading the
     * session without its monitor could see that list mid-write.
     */
    public void sendState(DuelSession session, long playerId) {
        DuelMessages.DuelState state;
        synchronized (session) {
            int elapsed = (int) Duration.between(session.turnStartedAt(), Instant.now()).toMillis();
            int timeLeft = Math.max(0, props.duel().turnSeconds() * 1000 - elapsed);
            long opponent = session.opponentOf(playerId);

            state = new DuelMessages.DuelState(
                    session.id(),
                    chainFor(session, playerId),
                    session.turn() == playerId,
                    String.valueOf(session.requiredLetter()),
                    timeLeft,
                    props.duel().turnSeconds(),
                    session.wordsBy(playerId),
                    session.wordsBy(opponent),
                    session.turn() != playerId);
        }
        sockets.send(playerId, "duel.update", state);
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
