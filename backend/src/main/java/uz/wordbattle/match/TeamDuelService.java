package uz.wordbattle.match;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Random;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import jakarta.annotation.PreDestroy;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.stereotype.Service;
import uz.wordbattle.config.AppProperties;
import uz.wordbattle.dictionary.DictionaryService;
import uz.wordbattle.friend.PresenceService;
import uz.wordbattle.match.MatchEntity.EndReason;
import uz.wordbattle.match.TeamDuelMessages.TeamChainEntry;
import uz.wordbattle.user.User;
import uz.wordbattle.user.UserDto;
import uz.wordbattle.user.UserService;
import uz.wordbattle.ws.SocketRegistry;

/**
 * Runs live 2v2 duels — the four-participant counterpart to {@link DuelService},
 * built the same way but never sharing a registry, a lock or a scheduler with
 * it: nothing in this class can change how a 1v1 duel behaves, and nothing in
 * {@link DuelService} had to move to make room for this one.
 *
 * <p>Turn order is the fixed rotation {@link TeamDuelSession} carries —
 * team-A-member-one, team-B-member-one, team-A-member-two, team-B-member-two —
 * and whichever of the two teams a losing turn belongs to is the team that
 * loses the whole duel, not just the one player who timed out, ran out of
 * moves or quit. There is no bot opponent for this mode and therefore no
 * bot-fallback path: {@link TeamMatchmakingService} only ever pairs two real
 * teams, and this class is never asked to start a duel any other way.
 */
@Service
public class TeamDuelService {

    private static final Logger log = LoggerFactory.getLogger(TeamDuelService.class);

    /** Same opening words {@link DuelService} seeds a chain with. */
    private static final List<String> SEED_WORDS =
            List.of("battle", "silver", "planet", "candle", "forest", "market", "window", "garden");

    /**
     * How long the result of a duel that ended while a player was away is kept
     * for their return — see {@link DuelService}'s field of the same name for
     * why this window and not a shorter or longer one.
     */
    private static final Duration MISSED_FINISH_TTL = Duration.ofMinutes(2);

    private record MissedFinish(TeamDuelMessages.TeamFinished frame, Instant at) {}

    /** The four players' profiles as they stood when the duel started. */
    private record Roster(UserDto teamAOne, UserDto teamATwo, UserDto teamBOne, UserDto teamBTwo) {}

    /** Same retry budget {@link DuelService#recordResult} gives a settlement the database refused. */
    private static final int SETTLE_ATTEMPTS = 8;

    private static final long SETTLEMENT_WAIT_SECONDS = 5;

    private final Map<String, TeamDuelSession> duels = new ConcurrentHashMap<>();
    private final Map<String, Roster> duelPlayers = new ConcurrentHashMap<>();
    private final Map<Long, String> teamDuelByPlayer = new ConcurrentHashMap<>();
    private final Map<Long, ScheduledFuture<?>> pendingForfeits = new ConcurrentHashMap<>();
    private final Map<Long, MissedFinish> missedFinishes = new ConcurrentHashMap<>();

    /** Guards the check-and-register in {@link #start}, exactly as {@code DuelService.startLock} does. */
    private final Object startLock = new Object();

    /**
     * A pool of its own rather than {@code DuelService}'s: a burst of 2v2
     * settlements must not delay a 1v1 turn timer, or the other way round, and
     * the two engines otherwise share nothing that would make borrowing one
     * pool for both worthwhile.
     */
    private final ScheduledExecutorService scheduler = Executors.newScheduledThreadPool(
            Math.max(2, Runtime.getRuntime().availableProcessors() / 2), runnable -> {
                Thread thread = new Thread(runnable, "team-duel-timer");
                thread.setDaemon(true);
                return thread;
            });
    private final Random random = new Random();

    private final AppProperties props;
    private final DictionaryService dictionary;
    private final SocketRegistry sockets;
    private final UserService users;
    private final PresenceService presence;
    private final TeamMatchResultService results;
    private final DuelService oneOnOneDuels;

    /**
     * {@code oneOnOneDuels} is read only for {@link DuelService#isPlaying(long)}
     * — the backstop in {@link #start} must refuse a player already mid-
     * 1v1-duel, not only one already mid-team-duel, or a player paired into
     * both at once by two unrelated queues would corrupt whichever registry
     * loses the race. {@link DuelService} has no reference back to this class,
     * so there is no cycle to build a {@code @Lazy} proxy around.
     */
    public TeamDuelService(
            AppProperties props,
            DictionaryService dictionary,
            SocketRegistry sockets,
            UserService users,
            PresenceService presence,
            TeamMatchResultService results,
            DuelService oneOnOneDuels) {
        this.props = props;
        this.dictionary = dictionary;
        this.sockets = sockets;
        this.users = users;
        this.presence = presence;
        this.results = results;
        this.oneOnOneDuels = oneOnOneDuels;
    }

    /** Ends every live 2v2 duel unrated on shutdown — see {@code DuelService.shutdown}. */
    @PreDestroy
    void shutdown() {
        for (TeamDuelSession session : List.copyOf(duels.values())) {
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

    /**
     * Starts a 2v2 duel between two already-matched teams. Null if any of the
     * four is already playing (either mode) or banned — the same backstop
     * {@code DuelService.start} is, for the same race between a team being
     * paired twice.
     */
    public TeamDuelSession start(
            long teamAMemberOne, long teamAMemberTwo, long teamBMemberOne, long teamBMemberTwo) {
        String seed = SEED_WORDS.get(random.nextInt(SEED_WORDS.size()));
        TeamDuelSession session = new TeamDuelSession(
                UUID.randomUUID().toString(),
                teamAMemberOne, teamAMemberTwo, teamBMemberOne, teamBMemberTwo,
                seed, props.duel().rareLetters());

        User a1 = users.require(teamAMemberOne);
        User a2 = users.require(teamAMemberTwo);
        User b1 = users.require(teamBMemberOne);
        User b2 = users.require(teamBMemberTwo);
        if (a1.isBanned() || a2.isBanned() || b1.isBanned() || b2.isBanned()) {
            log.warn("Refusing team duel {} vs {}: a player is banned", teamA(session), teamB(session));
            return null;
        }

        Roster roster = new Roster(UserDto.of(a1), UserDto.of(a2), UserDto.of(b1), UserDto.of(b2));

        synchronized (startLock) {
            if (busyAnywhere(teamAMemberOne) || busyAnywhere(teamAMemberTwo)
                    || busyAnywhere(teamBMemberOne) || busyAnywhere(teamBMemberTwo)) {
                log.warn("Refusing team duel {} vs {}: already playing", teamA(session), teamB(session));
                return null;
            }
            duels.put(session.id(), session);
            duelPlayers.put(session.id(), roster);
            for (long playerId : session.order()) {
                teamDuelByPlayer.put(playerId, session.id());
                presence.battleStarted(playerId);
                missedFinishes.remove(playerId);
            }
        }

        for (long playerId : session.order()) {
            announce(session, playerId);
        }

        synchronized (session) {
            armTurnTimer(session);
        }
        log.info("Team duel {} started: {} vs {}", session.id(), teamA(session), teamB(session));
        return session;
    }

    private List<Long> teamA(TeamDuelSession session) {
        return session.teamA();
    }

    private List<Long> teamB(TeamDuelSession session) {
        return session.teamB();
    }

    private void announce(TeamDuelSession session, long playerId) {
        sockets.send(playerId, "team_duel.match_found", new TeamDuelMessages.TeamMatchFound(
                session.id(),
                partnerFor(session, playerId),
                opponentOneFor(session, playerId),
                opponentTwoFor(session, playerId),
                true,
                session.turn() == playerId,
                session.turn(),
                session.chain().get(0).word(),
                String.valueOf(session.requiredLetter()),
                substitutedFrom(session),
                props.duel().turnSeconds(),
                chainFor(session, playerId)));
    }

    private UserDto partnerFor(TeamDuelSession session, long playerId) {
        return userDtoOf(session, session.partnerOf(playerId));
    }

    private UserDto opponentOneFor(TeamDuelSession session, long playerId) {
        return userDtoOf(session, session.opposingTeamOf(playerId).get(0));
    }

    private UserDto opponentTwoFor(TeamDuelSession session, long playerId) {
        return userDtoOf(session, session.opposingTeamOf(playerId).get(1));
    }

    /** Null only for a duel already taken out of the registries — see {@code DuelService.opponentFor}. */
    private UserDto userDtoOf(TeamDuelSession session, long playerId) {
        Roster roster = duelPlayers.get(session.id());
        if (roster == null) return null;
        List<Long> teamA = session.teamA();
        if (playerId == teamA.get(0)) return roster.teamAOne();
        if (playerId == teamA.get(1)) return roster.teamATwo();
        List<Long> teamB = session.teamB();
        if (playerId == teamB.get(0)) return roster.teamBOne();
        return roster.teamBTwo();
    }

    private String substitutedFrom(TeamDuelSession session) {
        Character skipped = session.substitutedFrom();
        return skipped == null ? null : String.valueOf(skipped);
    }

    // --------------------------------------------------------------- moves

    /** A player's word — validated exactly as {@code DuelService.submit} validates one. */
    public void submit(long playerId, String rawWord) {
        TeamDuelSession session = teamDuelOf(playerId).orElse(null);
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

            // Reaching the target number of words wins the duel for the
            // player's whole team, not just for them.
            if (session.wordsBy(playerId) >= props.duel().wordsToWin()) {
                finish(session, session.isTeamA(playerId), EndReason.WORDS_LIMIT);
                return;
            }

            session.passTurnTo(session.next(playerId));
            broadcastState(session);
            armTurnTimer(session);
        }
    }

    /** Quitting, backing out of the duel screen, or losing the connection. */
    public void forfeit(long playerId) {
        forfeitFor(playerId);
    }

    /** Mirrors {@code DuelService.forfeitAndAwaitSettlement} — see there for why account deletion waits. */
    public void forfeitAndAwaitSettlement(long playerId) {
        Future<?> settlement = forfeitFor(playerId);
        if (settlement == null) return;
        try {
            settlement.get(SETTLEMENT_WAIT_SECONDS, TimeUnit.SECONDS);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        } catch (ExecutionException | TimeoutException e) {
            log.warn("Settlement for {} did not land within {}s", playerId, SETTLEMENT_WAIT_SECONDS);
        }
    }

    private Future<?> forfeitFor(long playerId) {
        TeamDuelSession session = teamDuelOf(playerId).orElse(null);
        if (session == null) return null;
        synchronized (session) {
            if (session.finished()) return null;
            // The forfeiting player's own team loses; the other wins.
            return finish(session, !session.isTeamA(playerId), EndReason.FORFEIT);
        }
    }

    /** Same validation {@code DuelService.validate} runs — the word-chain rules do not change per mode. */
    private String validate(TeamDuelSession session, String word) {
        if (word.isEmpty()) return "empty";
        if (word.length() > props.limits().maxWordLength()) return "too_long";
        if (!word.chars().allMatch(c -> c >= 'a' && c <= 'z')) return "letters_only";
        if (word.length() < props.duel().minWordLength()) return "too_short";
        if (word.charAt(0) != session.requiredLetter()) return "wrong_letter";
        if (session.alreadyUsed(word)) return "already_used";
        if (!dictionary.isValid(word)) return "not_a_word";
        return null;
    }

    private String messageFor(String code, TeamDuelSession session) {
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
        sockets.send(playerId, "team_duel.rejected", new DuelMessages.Rejected(code, message));
    }

    // --------------------------------------------------------------- social

    /** Same limits {@code DuelService}'s own social frames are held to. */
    private static final Duration SOCIAL_THROTTLE = Duration.ofMillis(400);

    private static final int CHAT_MAX_LENGTH = 200;

    private static final Set<String> ALLOWED_REACTIONS = Set.of("🔥", "😂", "👏", "😮", "🤝", "😢");

    /** One bucket for chat and reactions alike — see {@code DuelService.lastSocialAt}. */
    private final Map<Long, Instant> lastSocialAt = new ConcurrentHashMap<>();

    /**
     * A free-text message for the other three, validated exactly as
     * {@code DuelService.sendChat} validates a 1v1 one and just as ephemeral.
     * The sender is named in the frame because a recipient has three people it
     * could have come from, where a 1v1 recipient has only ever had one.
     */
    public void sendChat(long playerId, String rawText) {
        TeamDuelSession session = teamDuelOf(playerId).orElse(null);
        if (session == null || session.finished()) {
            sockets.sendError(playerId, "no_duel", "Faol jang topilmadi");
            return;
        }

        String trimmed = rawText == null ? "" : rawText.trim();
        if (trimmed.isEmpty()) {
            sockets.sendError(playerId, "empty_message", "Bo'sh xabar yuborib bo'lmaydi");
            return;
        }
        if (trimmed.length() > CHAT_MAX_LENGTH) {
            sockets.sendError(playerId, "message_too_long", "Xabar juda uzun (200 belgigacha)");
            return;
        }
        if (!allowSocialFrame(playerId)) return;

        broadcastToOthers(session, playerId, "team_duel.chat", Map.of("playerId", playerId, "text", trimmed));
    }

    /** A reaction from the fixed emoji set, shown to the other three. */
    public void sendReaction(long playerId, String emoji) {
        TeamDuelSession session = teamDuelOf(playerId).orElse(null);
        if (session == null || session.finished()) {
            sockets.sendError(playerId, "no_duel", "Faol jang topilmadi");
            return;
        }
        if (!ALLOWED_REACTIONS.contains(emoji)) {
            sockets.sendError(playerId, "invalid_reaction", "Noma'lum reaksiya");
            return;
        }
        if (!allowSocialFrame(playerId)) return;

        broadcastToOthers(session, playerId, "team_duel.reaction", Map.of("playerId", playerId, "emoji", emoji));
    }

    /** Everyone in the duel but the sender, who already knows what they sent. */
    private void broadcastToOthers(TeamDuelSession session, long senderId, String type, Object payload) {
        for (long recipientId : session.order()) {
            if (recipientId == senderId) continue;
            sockets.send(recipientId, type, payload);
        }
    }

    /** Mirrors {@code DuelService.allowSocialFrame} — same window, same per-player bucket. */
    private boolean allowSocialFrame(long playerId) {
        Instant now = Instant.now();
        Instant last = lastSocialAt.get(playerId);
        if (last != null && Duration.between(last, now).compareTo(SOCIAL_THROTTLE) < 0) {
            sockets.sendError(playerId, "too_fast", "Sekinroq");
            return false;
        }
        lastSocialAt.put(playerId, now);
        return true;
    }

    // ---------------------------------------------------------- disconnects

    /** Mirrors {@code DuelService.connectionLost} — same grace window, same reason for it. */
    public void connectionLost(long playerId) {
        if (teamDuelOf(playerId).isEmpty()) return;
        ScheduledFuture<?> previous = pendingForfeits.put(
                playerId,
                scheduler.schedule(
                        () -> forfeitIfStillAway(playerId), DuelService.DISCONNECT_GRACE_SECONDS, TimeUnit.SECONDS));
        if (previous != null) previous.cancel(false);
    }

    public void connectionRestored(long playerId) {
        ScheduledFuture<?> pending = pendingForfeits.remove(playerId);
        if (pending != null) pending.cancel(false);
    }

    private void forfeitIfStillAway(long playerId) {
        pendingForfeits.remove(playerId);
        if (sockets.isConnected(playerId)) return;
        log.info("Player {} stayed away for {}s, forfeiting their team", playerId, DuelService.DISCONNECT_GRACE_SECONDS);
        forfeit(playerId);
    }

    /** Mirrors {@code DuelService.sendMissedFinish} — called on reconnect when there is no live duel. */
    public void sendMissedFinish(long playerId) {
        MissedFinish missed = missedFinishes.remove(playerId);
        if (missed == null || missed.at().isBefore(Instant.now().minus(MISSED_FINISH_TTL))) return;
        if (!sockets.send(playerId, "team_duel.finished", missed.frame())) {
            missedFinishes.putIfAbsent(playerId, missed);
        }
    }

    private void rememberMissedFinish(long playerId, TeamDuelMessages.TeamFinished frame) {
        Instant now = Instant.now();
        missedFinishes.values().removeIf(missed -> missed.at().isBefore(now.minus(MISSED_FINISH_TTL)));
        missedFinishes.put(playerId, new MissedFinish(frame, now));
    }

    // --------------------------------------------------------------- timers

    private void armTurnTimer(TeamDuelSession session) {
        long millis = props.duel().turnSeconds() * 1000L;
        long armedForTurn = session.turnNumber();
        session.setTurnTimer(
                scheduler.schedule(() -> onTurnExpired(session, armedForTurn), millis, TimeUnit.MILLISECONDS));
    }

    /** Times out whoever is sitting on the turn — see {@code DuelService.onTurnExpired} for the race this guards. */
    void onTurnExpired(TeamDuelSession session, long armedForTurn) {
        synchronized (session) {
            if (session.finished()) return;
            if (session.turnNumber() != armedForTurn) return;
            long loser = session.turn();
            finish(session, !session.isTeamA(loser), EndReason.TIMEOUT);
        }
    }

    // -------------------------------------------------------------- finish

    /** @return the settlement scheduled for it, or null if the duel had already ended. */
    private Future<?> finish(TeamDuelSession session, boolean teamAWon, EndReason reason) {
        if (!session.finish()) return null;
        deregister(session);
        return scheduler.submit(() -> settle(session, teamAWon, reason));
    }

    private void settle(TeamDuelSession session, boolean teamAWon, EndReason reason) {
        TeamMatchResultService.Outcome outcome = recordResult(session, teamAWon, reason);
        try {
            for (long playerId : session.order()) {
                notifyFinish(session, playerId, teamAWon, reason, outcome);
            }
        } catch (RuntimeException e) {
            log.error("Team duel {} could not be reported to its players", session.id(), e);
        }
        log.info("Team duel {} finished: teamAWon={} reason={}", session.id(), teamAWon, reason);
    }

    /** Same retry-on-optimistic-lock discipline as {@code DuelService.recordResult}. */
    private TeamMatchResultService.Outcome recordResult(TeamDuelSession session, boolean teamAWon, EndReason reason) {
        for (int attempt = 1; attempt <= SETTLE_ATTEMPTS; attempt++) {
            try {
                return results.record(session, teamAWon, reason);
            } catch (OptimisticLockingFailureException e) {
                log.warn("Team duel {} settlement lost a race for a player's row (attempt {} of {})",
                        session.id(), attempt, SETTLE_ATTEMPTS);
                pauseBeforeRetry(attempt);
            } catch (RuntimeException e) {
                log.error("Team duel {} could not be settled", session.id(), e);
                return TeamMatchResultService.Outcome.unrecorded();
            }
        }
        log.error("Team duel {} gave up settling after {} attempts", session.id(), SETTLE_ATTEMPTS);
        return TeamMatchResultService.Outcome.unrecorded();
    }

    private void pauseBeforeRetry(int attempt) {
        try {
            Thread.sleep(attempt * (5L + random.nextInt(20)));
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    /** Ends every live duel unrated — used only when the server itself is going away. */
    private void abort(TeamDuelSession session) {
        if (!session.finish()) return;
        deregister(session);
        for (long playerId : session.order()) {
            sockets.send(playerId, "team_duel.aborted", Map.of(
                    "duelId", session.id(),
                    "message", "Server qayta ishga tushmoqda — jang bekor qilindi"));
        }
        log.info("Team duel {} aborted (shutdown)", session.id());
    }

    private void deregister(TeamDuelSession session) {
        duels.remove(session.id(), session);
        duelPlayers.remove(session.id());
        for (long playerId : session.order()) {
            if (teamDuelByPlayer.remove(playerId, session.id())) {
                presence.battleEnded(playerId);
            }
        }
    }

    private void notifyFinish(
            TeamDuelSession session, long playerId, boolean teamAWon, EndReason reason,
            TeamMatchResultService.Outcome outcome) {

        // A player who has already moved on to a new duel must not be told
        // this one's result on their live socket — see DuelService.notifyFinish
        // for the reconnect race this guards against.
        TeamDuelSession current = teamDuelOf(playerId).orElse(null);
        if (current != null && current != session) {
            log.info("Team duel {} result withheld from {}: they are already in duel {}",
                    session.id(), playerId, current.id());
            return;
        }

        TeamMatchResultService.PlayerResult result = outcome.forPlayer(playerId);
        boolean won = teamAWon == session.isTeamA(playerId);

        String stuckLetter = null;
        List<String> hints = List.of();
        if (!won) {
            char letter = session.requiredLetter();
            stuckLetter = String.valueOf(Character.toUpperCase(letter));
            hints = dictionary.hints(letter, session.used(), 3);
        }

        TeamDuelMessages.TeamFinished frame = new TeamDuelMessages.TeamFinished(
                session.id(),
                won ? "win" : "lose",
                reason.name().toLowerCase(),
                result.delta(),
                result.ratingBefore(),
                result.ratingAfter(),
                session.chainLength(),
                session.wordsBy(playerId),
                session.averageMsOf(playerId),
                result.newWords(),
                result.streakDays(),
                stuckLetter,
                hints,
                partnerFor(session, playerId),
                opponentOneFor(session, playerId),
                opponentTwoFor(session, playerId));

        deliverFinish(playerId, frame);
    }

    private void deliverFinish(long playerId, TeamDuelMessages.TeamFinished frame) {
        if (sockets.send(playerId, "team_duel.finished", frame)) return;
        rememberMissedFinish(playerId, frame);
        if (sockets.isConnected(playerId) && !isPlaying(playerId)) sendMissedFinish(playerId);
    }

    // ---------------------------------------------------------------- state

    private void broadcastState(TeamDuelSession session) {
        for (long playerId : session.order()) {
            sendState(session, playerId);
        }
    }

    /** Mirrors {@code DuelService.sendState} — callable from any thread, silent for an already-finished duel. */
    public void sendState(TeamDuelSession session, long playerId) {
        TeamDuelMessages.TeamDuelState state;
        synchronized (session) {
            if (session.finished()) return;

            int elapsed = (int) Duration.between(session.turnStartedAt(), Instant.now()).toMillis();
            int timeLeft = Math.max(0, props.duel().turnSeconds() * 1000 - elapsed);
            long partner = session.partnerOf(playerId);
            long opponentOne = session.opposingTeamOf(playerId).get(0);
            long opponentTwo = session.opposingTeamOf(playerId).get(1);

            state = new TeamDuelMessages.TeamDuelState(
                    session.id(),
                    partnerFor(session, playerId),
                    opponentOneFor(session, playerId),
                    opponentTwoFor(session, playerId),
                    chainFor(session, playerId),
                    session.turn() == playerId,
                    session.turn(),
                    String.valueOf(session.requiredLetter()),
                    substitutedFrom(session),
                    timeLeft,
                    props.duel().turnSeconds(),
                    session.wordsBy(playerId),
                    session.wordsBy(partner),
                    session.wordsBy(opponentOne),
                    session.wordsBy(opponentTwo));
        }
        sockets.send(playerId, "team_duel.update", state);
    }

    private List<TeamChainEntry> chainFor(TeamDuelSession session, long playerId) {
        long partner = session.partnerOf(playerId);
        List<TeamChainEntry> out = new ArrayList<>();
        for (DuelSession.ChainWord word : session.chain()) {
            out.add(new TeamChainEntry(
                    word.word(), word.playerId(), word.playerId() == playerId, word.playerId() == partner, word.spentMs()));
        }
        return out;
    }

    public Optional<TeamDuelSession> teamDuelOf(long playerId) {
        String id = teamDuelByPlayer.get(playerId);
        return id == null ? Optional.empty() : Optional.ofNullable(duels.get(id));
    }

    public boolean isPlaying(long playerId) {
        return teamDuelOf(playerId).isPresent();
    }

    /** Playing anything at all — a 1v1 duel or a team duel. See the constructor note on {@link #oneOnOneDuels}. */
    private boolean busyAnywhere(long playerId) {
        return isPlaying(playerId) || oneOnOneDuels.isPlaying(playerId);
    }
}
