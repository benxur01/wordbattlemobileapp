package uz.wordbattle.tournament;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface TournamentMatchRepository extends JpaRepository<TournamentMatch, Long> {

    List<TournamentMatch> findByTournamentIdOrderByRoundAscSlotAsc(Long tournamentId);

    Optional<TournamentMatch> findByTournamentIdAndRoundAndSlot(Long tournamentId, int round, int slot);

    /**
     * A player's matches that are filled and waiting for somebody to start them
     * — sent again on reconnect, since a {@code tournament.match_ready} push is
     * only ever delivered while the socket is open. The two partner columns are
     * matched as well so a team's second member is told about their own match:
     * they are null throughout a {@code SOLO} bracket, so this returns exactly
     * the rows it always did for one.
     */
    @Query("""
            select m from TournamentMatch m
            where m.status = uz.wordbattle.tournament.TournamentMatch.Status.READY
              and (m.playerOneUserId = :userId or m.playerTwoUserId = :userId
                   or m.playerOnePartnerUserId = :userId or m.playerTwoPartnerUserId = :userId)
            """)
    List<TournamentMatch> findReadyFor(@Param("userId") Long userId);
}
