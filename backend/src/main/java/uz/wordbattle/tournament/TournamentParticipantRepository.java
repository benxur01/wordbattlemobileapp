package uz.wordbattle.tournament;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface TournamentParticipantRepository extends JpaRepository<TournamentParticipant, Long> {

    List<TournamentParticipant> findByTournamentIdOrderByIdAsc(Long tournamentId);

    Optional<TournamentParticipant> findByTournamentIdAndUserId(Long tournamentId, Long userId);

    List<TournamentParticipant> findByTournamentIdAndStatus(Long tournamentId, TournamentParticipant.Status status);

    /** Every tournament a player has ever been invited to, newest invite first. */
    List<TournamentParticipant> findByUserIdOrderByInvitedAtDesc(Long userId);

    List<TournamentParticipant> findByUserIdAndStatus(Long userId, TournamentParticipant.Status status);
}
