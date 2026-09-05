package uz.wordbattle.tournament;

import java.util.List;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

public interface TournamentRepository extends JpaRepository<TournamentEntity, Long> {

    Page<TournamentEntity> findAllByOrderByIdDesc(Pageable pageable);

    /**
     * The lobby's "an active tournament exists" discovery banner, bounded so
     * this never scans the whole table — see {@code app_root.dart}'s "take the
     * first" for why a {@code GLOBAL} one, if one is being played, is worth
     * sorting ahead of everything else rather than just the most recent.
     */
    @Query("select t from TournamentEntity t where t.status = uz.wordbattle.tournament.TournamentEntity.Status.IN_PROGRESS "
            + "order by case when t.kind = uz.wordbattle.tournament.TournamentEntity.Kind.GLOBAL then 0 else 1 end, "
            + "t.startedAt desc")
    List<TournamentEntity> findActive(Pageable pageable);

    /**
     * The browse screen's discoverable list. A tournament that is {@code OPEN}
     * and {@code PRIVATE} is only ever waiting on its own organizer's guest
     * list — meaningless to a stranger scrolling past it — so this is
     * everything else: open to the public, in progress (spectating is already
     * open to all), or finished.
     */
    @Query("select t from TournamentEntity t where not ("
            + "t.status = uz.wordbattle.tournament.TournamentEntity.Status.OPEN "
            + "and t.visibility = uz.wordbattle.tournament.TournamentEntity.Visibility.PRIVATE) "
            + "order by t.id desc")
    List<TournamentEntity> findBrowsable(Pageable pageable);

    /** The weekly scheduler's own "don't overlap" guard — one Global tournament open or being played at a time. */
    @Query("select count(t) > 0 from TournamentEntity t where t.kind = uz.wordbattle.tournament.TournamentEntity.Kind.GLOBAL "
            + "and t.status in (uz.wordbattle.tournament.TournamentEntity.Status.OPEN, "
            + "uz.wordbattle.tournament.TournamentEntity.Status.IN_PROGRESS)")
    boolean existsActiveGlobal();
}
