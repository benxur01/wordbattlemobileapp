package uz.wordbattle.ws;

import org.springframework.stereotype.Component;
import uz.wordbattle.match.DuelService;
import uz.wordbattle.match.InviteService;
import uz.wordbattle.match.MatchmakingService;
import uz.wordbattle.match.TeamDuelService;
import uz.wordbattle.match.TeamInviteService;
import uz.wordbattle.match.TeamMatchmakingService;
import uz.wordbattle.match.TeamService;
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
    private final TeamMatchmakingService teamMatchmaking;
    private final TeamInviteService teamInvites;
    private final TeamService teams;
    private final TeamDuelService teamDuels;

    public SocketSessionEnder(
            SocketRegistry sockets,
            MatchmakingService matchmaking,
            DuelService duels,
            InviteService invites,
            TeamMatchmakingService teamMatchmaking,
            TeamInviteService teamInvites,
            TeamService teams,
            TeamDuelService teamDuels) {
        this.sockets = sockets;
        this.matchmaking = matchmaking;
        this.duels = duels;
        this.invites = invites;
        this.teamMatchmaking = teamMatchmaking;
        this.teamInvites = teamInvites;
        this.teams = teams;
        this.teamDuels = teamDuels;
    }

    @Override
    public void endSessionOf(long userId) {
        // The socket goes first — before the teardown below, and above all
        // before the wait inside it. Every way into a duel passes through the
        // registry: matchmaking pairs nobody it cannot reach, an invite is
        // neither sent to nor accepted by a player with no socket, and every
        // other start is a frame this player would have had to send. Closing it
        // last, as this used to, left the socket open and authenticated for as
        // long as the settlement took — up to five seconds — and a duel started
        // in that window was one nothing had waited for. It settled after the
        // account was erased and wrote a rating, a battle count and fresh
        // rating-history rows onto the anonymous shell. MatchResultService
        // refuses those writes too; this is what stops the duel from starting
        // at all, which is the only place the opponent is spared a duel against
        // somebody who is already gone.
        //
        // Nothing is lost by closing early. The close callback finds no entry
        // under this id, reads its own close as a socket that has been replaced
        // and returns without tearing anything down — which is why the three
        // calls below are here in the first place, and they work the same
        // whichever side of them the socket is closed on.
        sockets.disconnect(userId);
        matchmaking.leave(userId);
        invites.cancelAllFor(userId);
        // Walking out mid-duel is a forfeit, exactly as quitting is — the
        // opponent should not be left waiting on a player who no longer exists.
        // The result is waited for rather than left in flight: the caller is
        // about to erase this player's rows, and a settlement landing after it
        // would write their learned words and rating history back in.
        duels.forfeitAndAwaitSettlement(userId);
        // Same teardown, and the same wait, for the 2v2 mode.
        teamMatchmaking.leave(userId);
        teamInvites.cancelAllFor(userId);
        teams.cancelAllFor(userId);
        teamDuels.forfeitAndAwaitSettlement(userId);
    }
}
