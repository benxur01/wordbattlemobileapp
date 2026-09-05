package uz.wordbattle.tournament;

import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.PageRequest;
import org.springframework.scheduling.annotation.SchedulingConfigurer;
import org.springframework.scheduling.config.ScheduledTaskRegistrar;
import org.springframework.scheduling.support.CronTrigger;
import org.springframework.stereotype.Component;
import uz.wordbattle.config.AppProperties;
import uz.wordbattle.user.User;
import uz.wordbattle.user.UserRepository;

/**
 * Opens a fresh Global tournament every week, so a player never has to wait on
 * an admin or a friend to run one — {@link TournamentService#join} is the only
 * way into it.
 *
 * <p>The cron expression and its zone are read off {@link AppProperties}
 * rather than spelled into a {@code @Scheduled} annotation's placeholder: the
 * test suite's own {@code application.yml} replaces the shipped one entirely
 * and does not restate this section, so a placeholder here would fail to
 * resolve the moment a test tried to load this bean — see {@code
 * AppProperties}'s own javadoc for why every tunable falls back to a {@code
 * @DefaultValue} instead, which only works this way, through the bean.
 *
 * <p>The rating floor is a snapshot, not a fixed guest list: it is whichever
 * rating the Nth-best player holds the moment this runs, taken off {@link
 * UserRepository#topByRating}. A slot the top player never claims is still
 * open to whoever is next best — the floor decides who may try for a seat, not
 * who is handed one.
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
        AppProperties.Tournament.Global config = props.tournament().global();
        registrar.addTriggerTask(this::openWeeklyTournament, new CronTrigger(config.cron(), props.timeZone()));
    }

    public void openWeeklyTournament() {
        // One Global tournament at a time — a new one every week is pointless
        // while last week's is still open or still being played.
        if (tournaments.existsActiveGlobal()) return;

        int size = props.tournament().global().size();
        List<User> ranked = users.topByRating(PageRequest.of(0, size));
        // Nobody with a nickname to be ranked by yet — nothing to open a
        // bracket over.
        if (ranked.isEmpty()) return;

        double minRating = ranked.get(ranked.size() - 1).getRating();
        TournamentEntity created = tournamentService.createGlobalTournament(size, minRating);
        log.info("Opened weekly Global tournament {} (size {}, rating floor {})", created.getId(), size, minRating);
    }
}
