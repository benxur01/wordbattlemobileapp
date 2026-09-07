package uz.wordbattle.tournament;

import java.util.List;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

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
     * and {@code PRIVATE} is only ever waiting on a guest list — its
     * organizer's, or the ladder's own for a {@code GLOBAL} one — which is
     * meaningless to a stranger scrolling past it, so this is everything else:
     * open to the public, in progress (spectating is already open to all), or
     * finished. A Global bracket therefore appears here the moment it starts
     * and not before, which is the moment there is anything to watch.
     */
    @Query("select t from TournamentEntity t where not ("
            + "t.status = uz.wordbattle.tournament.TournamentEntity.Status.OPEN "
            + "and t.visibility = uz.wordbattle.tournament.TournamentEntity.Visibility.PRIVATE) "
            + "order by t.id desc")
    List<TournamentEntity> findBrowsable(Pageable pageable);

    /**
     * The weekly scheduler's own "don't overlap" guard — one Global tournament
     * of this format open or being played at a time. Asked per format, because
     * the 1v1 bracket and the 2v2 one run their own weeks and neither being
     * live is a reason for the other to skip its own.
     */
    @Query("select count(t) > 0 from TournamentEntity t where t.kind = uz.wordbattle.tournament.TournamentEntity.Kind.GLOBAL "
            + "and t.format = :format "
            + "and t.status in (uz.wordbattle.tournament.TournamentEntity.Status.OPEN, "
            + "uz.wordbattle.tournament.TournamentEntity.Status.IN_PROGRESS)")
    boolean existsActiveGlobal(@Param("format") TournamentEntity.Format format);

    /** Brackets still waiting on their invited players — all the expiry sweep has any business touching. */
    @Query("select t from TournamentEntity t where t.kind = uz.wordbattle.tournament.TournamentEntity.Kind.GLOBAL "
            + "and t.status = uz.wordbattle.tournament.TournamentEntity.Status.OPEN")
    List<TournamentEntity> findOpenGlobal();
}
