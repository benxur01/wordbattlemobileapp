package uz.wordbattle.tournament;

import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.PageRequest;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.scheduling.annotation.SchedulingConfigurer;
import org.springframework.scheduling.config.ScheduledTaskRegistrar;
import org.springframework.scheduling.support.CronTrigger;
import org.springframework.stereotype.Component;
import uz.wordbattle.config.AppProperties;
import uz.wordbattle.user.User;
import uz.wordbattle.user.UserRepository;

/**
 * Opens a fresh Global tournament every week, so a player never has to wait on
 * an admin or a friend to run one — and a 2v2 one an hour behind it. The two
 * are guarded apart: neither being live is a reason for the other to skip its
 * own week.
 *
 * <p>Nobody is invited to a Global bracket by a person, because there is no
 * person: the moment one opens, {@link TournamentService#inviteTopRankedSolo}
 * — or {@link TournamentService#inviteTopRankedTeam} for the 2v2 one — offers
 * it to the top of the ladder, and each of them answers as they would answer a
 * friend's invite. A seat turned down is offered on down the ladder, and so is
 * one left unanswered: see {@link #expireStaleInvites} for the silence half of
 * that, which is the common one.
 *
 * <p>A bracket opens on Monday and kicks off at a fixed hour on Sunday —
 * {@link #finalizeWeeklyTournament} — whether or not it filled, and equally
 * whether or not it filled early: the one tournament everybody is in is at an
 * hour a player can plan around, so nothing about how quickly the invites came
 * back moves it. What a quiet week changes is the size, not the time. The
 * bracket shrinks to the largest the accepted seats fill rather than being
 * called off, so a quiet week is a smaller tournament and not a missing one.
 *
 * <p>The cron expression and its zone are read off {@link AppProperties}
 * rather than spelled into a {@code @Scheduled} annotation's placeholder: the
 * test suite's own {@code application.yml} replaces the shipped one entirely
 * and does not restate this section, so a placeholder here would fail to
 * resolve the moment a test tried to load this bean — see {@code
 * AppProperties}'s own javadoc for why every tunable falls back to a {@code
 * @DefaultValue} instead, which only works this way, through the bean. The
 * sweep below carries a plain {@code @Scheduled} because its interval is a
 * literal and resolves without the file.
 *
 * <p>The rating recorded on the bracket is a snapshot of how strong this
 * week's field is — the weakest player invited, taken off {@link
 * UserRepository#topEligibleByRating} — and is shown rather than enforced.
 * Nothing gates on it now that the invitations decide who plays.
 */
@Component
public class GlobalTournamentScheduler implements SchedulingConfigurer {

    private static final Logger log = LoggerFactory.getLogger(GlobalTournamentScheduler.class);

    private final TournamentRepository tournaments;
    private final TournamentService tournamentService;
    private final UserRepository users;
    private final AppProperties props;

    public GlobalTournamentScheduler(
            TournamentRepository tournaments,
            TournamentService tournamentService,
            UserRepository users,
            AppProperties props) {
        this.tournaments = tournaments;
        this.tournamentService = tournamentService;
        this.users = users;
        this.props = props;
    }

    @Override
    public void configureTasks(ScheduledTaskRegistrar registrar) {
        AppProperties.Tournament.Global solo = props.tournament().global();
        AppProperties.Tournament.GlobalTeam team = props.tournament().globalTeam();
        registrar.addTriggerTask(this::openWeeklyTournament, new CronTrigger(solo.cron(), props.timeZone()));
        registrar.addTriggerTask(this::openWeeklyTeamTournament, new CronTrigger(team.cron(), props.timeZone()));
        registrar.addTriggerTask(
                this::finalizeWeeklyTournament, new CronTrigger(solo.finalizeCron(), props.timeZone()));
        registrar.addTriggerTask(
                this::finalizeWeeklyTeamTournament, new CronTrigger(team.finalizeCron(), props.timeZone()));
    }

    public void openWeeklyTournament() {
        // One Global tournament of each format at a time — a new one every week
        // is pointless while last week's is still open or still being played.
        if (tournaments.existsActiveGlobal(TournamentEntity.Format.SOLO)) return;

        int size = props.tournament().global().size();
        List<User> ranked = users.topEligibleByRating(PageRequest.of(0, size));
        // Nobody with a nickname to be ranked by yet — nothing to open a
        // bracket over.
        if (ranked.isEmpty()) return;

        double minRating = ranked.get(ranked.size() - 1).getRating();
        TournamentEntity created = tournamentService.createGlobalTournament(size, minRating);
        tournamentService.inviteTopRankedSolo(created);
        log.info("Opened weekly Global tournament {} (size {}, weakest invited {})", created.getId(), size, minRating);
    }

    /**
     * The 2v2 bracket, whose {@code size} counts teams rather than players, so
     * twice as many people are invited — paired into seats by
     * {@link TournamentService#inviteTopRankedTeam}.
     */
    public void openWeeklyTeamTournament() {
        if (tournaments.existsActiveGlobal(TournamentEntity.Format.TEAM)) return;

        int size = props.tournament().globalTeam().size();
        List<User> ranked = users.topEligibleByRating(PageRequest.of(0, size * 2));
        if (ranked.isEmpty()) return;

        double minRating = ranked.get(ranked.size() - 1).getRating();
        TournamentEntity created = tournamentService.createGlobalTeamTournament(size, minRating);
        tournamentService.inviteTopRankedTeam(created);
        log.info(
                "Opened weekly Global 2v2 tournament {} (size {} teams, weakest invited {})",
                created.getId(),
                size,
                minRating);
    }

    /** Sunday's kickoff for the 1v1 bracket — see {@link TournamentService#finalizeOpenGlobal}. */
    public void finalizeWeeklyTournament() {
        logFinalized(TournamentEntity.Format.SOLO);
    }

    /** The same half an hour later for the 2v2 one, so the two never kick off in the same instant. */
    public void finalizeWeeklyTeamTournament() {
        logFinalized(TournamentEntity.Format.TEAM);
    }

    private void logFinalized(TournamentEntity.Format format) {
        for (TournamentEntity closed : tournamentService.finalizeOpenGlobal(format)) {
            log.info(
                    "Closed weekly Global {} tournament {}: {} with {} seat(s)",
                    format,
                    closed.getId(),
                    closed.getStatus(),
                    closed.getSize());
        }
    }

    /**
     * Gives up on Global invites nobody answered and offers those seats on down
     * the ladder. Every half-hour rather than on the weekly cron: an invite's
     * patience is measured in hours, and a bracket that has just been refilled
     * should not wait until Sunday to notice the replacement went quiet too.
     *
     * <p>Global brackets only — see {@link
     * TournamentService#expireStaleGlobalInvites}, which is where the rule
     * itself lives.
     */
    @Scheduled(fixedDelay = 30 * 60 * 1000L)
    public void expireStaleInvites() {
        int expired = tournamentService.expireStaleGlobalInvites(props.tournament().global().inviteTtl());
        if (expired > 0) log.info("Expired {} unanswered Global tournament invite(s)", expired);
    }
}
