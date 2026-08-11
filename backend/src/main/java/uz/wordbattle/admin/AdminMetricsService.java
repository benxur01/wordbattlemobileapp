package uz.wordbattle.admin;

import java.time.Instant;
import java.time.LocalDate;
import org.springframework.stereotype.Service;
import uz.wordbattle.config.AppProperties;
import uz.wordbattle.match.MatchRepository;
import uz.wordbattle.user.UserRepository;

/** The handful of numbers on the panel's front page. */
@Service
public class AdminMetricsService {

    /**
     * @param totalUsers live accounts. A deleted one is an anonymous shell an
     *     old match points at, and counting it would make the server look busier
     *     than it is.
     * @param botBattles and {@code humanBattles} split every duel ever settled,
     *     which is the one ratio that says whether players are finding each
     *     other or being handed to the fallback bot.
     */
    public record Metrics(
            long totalUsers,
            long bannedUsers,
            long battlesToday,
            long botBattles,
            long humanBattles) {}

    private final UserRepository users;
    private final MatchRepository matches;
    private final AppProperties props;

    public AdminMetricsService(UserRepository users, MatchRepository matches, AppProperties props) {
        this.users = users;
        this.matches = matches;
        this.props = props;
    }

    public Metrics snapshot() {
        long bot = matches.countByBotOpponentTrue();
        return new Metrics(
                users.countLive(),
                users.countBanned(),
                matches.countFinishedSince(startOfToday()),
                bot,
                matches.count() - bot);
    }

    /**
     * Local midnight, not UTC — the same day the streaks and the practice word
     * roll over on. In UTC "today" would start at 05:00 for the players this is
     * being counted for, and the number on the dashboard would be wrong for the
     * whole of the morning.
     */
    private Instant startOfToday() {
        return LocalDate.now(props.timeZone()).atStartOfDay(props.timeZone()).toInstant();
    }
}
