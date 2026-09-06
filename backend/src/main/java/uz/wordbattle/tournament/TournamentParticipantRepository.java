package uz.wordbattle.tournament;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface TournamentParticipantRepository extends JpaRepository<TournamentParticipant, Long> {

    List<TournamentParticipant> findByTournamentIdOrderByIdAsc(Long tournamentId);

    Optional<TournamentParticipant> findByTournamentIdAndUserId(Long tournamentId, Long userId);

    List<TournamentParticipant> findByTournamentIdAndStatus(Long tournamentId, TournamentParticipant.Status status);

    /** Every tournament a player has ever been invited to, newest invite first. */
    List<TournamentParticipant> findByUserIdOrderByInvitedAtDesc(Long userId);

    /**
     * The seat this player holds in one tournament, as either half of it. The
     * same row {@link #findByTournamentIdAndUserId} returns for a {@code SOLO}
     * tournament, where no seat has a second member to be found by.
     */
    @Query("""
            select p from TournamentParticipant p
            where p.tournamentId = :tournamentId and (p.userId = :userId or p.partnerUserId = :userId)
            """)
    Optional<TournamentParticipant> findSeatOf(
            @Param("tournamentId") Long tournamentId, @Param("userId") Long userId);

    /**
     * Invites this player still owes an answer to — their own, whichever half
     * of a seat they were named as. A teammate's answer lives in its own
     * column, so a team whose primary member has already said yes still shows
     * up here for the one who has not.
     */
    @Query("""
            select p from TournamentParticipant p
            where (p.userId = :userId
                    and p.status = uz.wordbattle.tournament.TournamentParticipant.Status.INVITED)
               or (p.partnerUserId = :userId
                    and p.partnerStatus = uz.wordbattle.tournament.TournamentParticipant.Status.INVITED)
            """)
    List<TournamentParticipant> findPendingInvitesFor(@Param("userId") Long userId);
}
