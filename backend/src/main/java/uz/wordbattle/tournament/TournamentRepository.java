package uz.wordbattle.tournament;

import java.util.List;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

public interface TournamentRepository extends JpaRepository<TournamentEntity, Long> {

    Page<TournamentEntity> findAllByOrderByIdDesc(Pageable pageable);

    /** The lobby's "an active tournament exists" discovery banner. */
    @Query("select t from TournamentEntity t where t.status = uz.wordbattle.tournament.TournamentEntity.Status.IN_PROGRESS "
            + "order by t.startedAt desc")
    List<TournamentEntity> findActive();
}
