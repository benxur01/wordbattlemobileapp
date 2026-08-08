package uz.wordbattle.ws;

import org.springframework.stereotype.Component;
import uz.wordbattle.match.DuelService;
import uz.wordbattle.match.InviteService;
import uz.wordbattle.match.MatchmakingService;
import uz.wordbattle.user.AccountDeletionService;

/**
 * Tears down everything a player is currently part of. Used when an account is
 * deleted: the socket layer knows how to do this, and the user package should
 * not have to know the socket layer exists.
 */
@Component
public class SocketSessionEnder implements AccountDeletionService.SessionEnder {

    private final SocketRegistry sockets;
    private final MatchmakingService matchmaking;
    private final DuelService duels;
    private final InviteService invites;

    public SocketSessionEnder(
            SocketRegistry sockets, MatchmakingService matchmaking, DuelService duels, InviteService invites) {
        this.sockets = sockets;
        this.matchmaking = matchmaking;
        this.duels = duels;
        this.invites = invites;
    }

    @Override
    public void endSessionOf(long userId) {
        matchmaking.leave(userId);
        invites.cancelAllFor(userId);
        // Walking out mid-duel is a forfeit, exactly as quitting is — the
        // opponent should not be left waiting on a player who no longer exists.
        duels.forfeit(userId);
        sockets.disconnect(userId);
    }
}
