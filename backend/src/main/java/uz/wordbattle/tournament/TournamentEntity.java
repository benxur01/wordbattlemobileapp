package uz.wordbattle.tournament;

import jakarta.persistence.*;
import java.time.Instant;

/**
 * A single-elimination bracket: a name, a fixed power-of-two size, and no
 * money anywhere near it — that was cut deliberately after a legal discussion
 * about real-money prizes. Curated by the admin panel, by an ordinary player
 * organizing one among their own friends (since
 * {@link TournamentService#createByUser}), or — since {@code
 * GlobalTournamentScheduler} — by nobody at all: {@link #kind} tells the three
 * apart, {@link #createdByAdminId} names whichever human ran it and is null
 * only for the last one, and the rest of this class does not care which.
 *
 * <p>{@link #visibility} is the door {@link TournamentService#join} checks:
 * {@code PRIVATE} is invite-only and {@code PUBLIC} lets a stranger seat
 * themselves with nobody inviting them. A {@code GLOBAL} bracket is
 * {@code PRIVATE} too, and that is the whole of what closes self-join on one:
 * its guest list is the top of the ladder, invited by the system itself — see
 * {@link TournamentService#inviteTopRankedSolo} — so there is no seat left for
 * a stranger to claim, and {@code join} refuses one for exactly the reason it
 * refuses an admin's bracket.
 *
 * <p>{@link #format} decides what occupies a seat: one player ({@code SOLO},
 * every bracket that existed before 2v2 tournaments) or a pair of them
 * ({@code TEAM}). {@link #size} counts seats either way — a {@code TEAM}
 * bracket of 4 is four teams and therefore eight people.
 */
@Entity
@Table(name = "tournaments")
public class TournamentEntity {

    public enum Status {
        /** Admin is inviting players; nobody has been seeded into a bracket yet. */
        OPEN,
        /** The bracket is seeded and matches are being played. */
        IN_PROGRESS,
        /** The final has been decided. */
        COMPLETED,
        /** Called off early by its organizer or an admin — no champion, no more rounds. */
        CANCELLED
    }

    /** Whether a stranger may join themselves — see {@link TournamentService#join}. */
    public enum Visibility { PRIVATE, PUBLIC }

    /** Who runs the bracket: the admin panel, a player among their own friends, or nobody — see {@link #kind}. */
    public enum Kind { FRIEND, ADMIN, GLOBAL }

    /** What holds a seat: one player, or a pair of them playing every match as a 2v2 duel. */
    public enum Format { SOLO, TEAM }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "name", nullable = false, length = 64)
    private String name;

    /** A power of two — 4, 8, 16 or 32 — enforced by {@link TournamentService}. */
    @Column(name = "size", nullable = false)
    private int size;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private Status status;

    /** The organizer — an admin, or a player who started this one among friends. Null for a {@code GLOBAL} tournament. */
    @Column(name = "created_by_admin_id")
    private Long createdByAdminId;

    @Enumerated(EnumType.STRING)
    @Column(name = "visibility", nullable = false, length = 16)
    private Visibility visibility;

    @Enumerated(EnumType.STRING)
    @Column(name = "kind", nullable = false, length = 16)
    private Kind kind;

    @Enumerated(EnumType.STRING)
    @Column(name = "format", nullable = false, length = 16)
    private Format format;

    /**
     * How strong this week's field is: the rating of the weakest player the
     * bracket was opened to, set only on a {@code GLOBAL} tournament and null
     * otherwise. Shown rather than enforced — nothing gates on it now that a
     * Global bracket invites its players instead of waiting to be joined.
     */
    @Column(name = "min_rating")
    private Double minRating;

    /** Null until the final match is decided. */
    @Column(name = "champion_user_id")
    private Long championUserId;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt = Instant.now();

    @Column(name = "started_at")
    private Instant startedAt;

    @Column(name = "finished_at")
    private Instant finishedAt;

    protected TournamentEntity() {}

    private TournamentEntity(
            String name,
            int size,
            Long createdByAdminId,
            Visibility visibility,
            Kind kind,
            Format format,
            Double minRating) {
        this.name = name;
        this.size = size;
        this.createdByAdminId = createdByAdminId;
        this.visibility = visibility;
        this.kind = kind;
        this.format = format;
        this.minRating = minRating;
        this.status = Status.OPEN;
    }

    /** The friends screen's default — kept for whatever still calls it this way; always private and {@link Kind#FRIEND}. */
    public TournamentEntity(String name, int size, Long createdByAdminId) {
        this(name, size, createdByAdminId, Kind.FRIEND);
    }

    /** The admin panel and the friends screen, tagged apart only for the browse list's badge — both start private. */
    public TournamentEntity(String name, int size, Long createdByAdminId, Kind kind) {
        this(name, size, createdByAdminId, Visibility.PRIVATE, kind, Format.SOLO, null);
    }

    /** The friends screen's self-service create, when the organizer asks for {@code PUBLIC} instead of the private default. */
    public TournamentEntity(String name, int size, Long createdByAdminId, Kind kind, Visibility visibility) {
        this(name, size, createdByAdminId, visibility, kind, Format.SOLO, null);
    }

    /** The same, when the organizer also asks for a 2v2 bracket instead of the one-player-per-seat default. */
    public TournamentEntity(String name, int size, Long createdByAdminId, Kind kind, Visibility visibility, Format format) {
        this(name, size, createdByAdminId, visibility, kind, format, null);
    }

    /**
     * {@code GlobalTournamentScheduler}'s own creation path — no organizer, and
     * invite-only like every other bracket: the invites go out from
     * {@link TournamentService#inviteTopRankedSolo} rather than from a person.
     */
    public static TournamentEntity global(String name, int size, double minRating) {
        return new TournamentEntity(name, size, null, Visibility.PRIVATE, Kind.GLOBAL, Format.SOLO, minRating);
    }

    /** The same for the weekly 2v2 bracket beside it, whose {@code size} counts teams rather than players. */
    public static TournamentEntity globalTeam(String name, int size, double minRating) {
        return new TournamentEntity(name, size, null, Visibility.PRIVATE, Kind.GLOBAL, Format.TEAM, minRating);
    }

    public Long getId() { return id; }
    public String getName() { return name; }
    public int getSize() { return size; }

    /**
     * Only {@link TournamentService#finalizeOpenGlobal} writes this, and only
     * to shrink a Global bracket the week did not fill to the number of seats
     * it actually has — a 32 that collected 11 becomes an 8. Everything that
     * reads {@link #size} reads it after that: {@link #rounds} lays out the
     * bracket from it, and {@code startInternal} refuses unless exactly this
     * many seats accepted, which is precisely what the finalize just made true.
     */
    public void setSize(int size) { this.size = size; }
    public Status getStatus() { return status; }
    public void setStatus(Status status) { this.status = status; }
    public Long getCreatedByAdminId() { return createdByAdminId; }
    public Visibility getVisibility() { return visibility; }
    public Kind getKind() { return kind; }
    public Format getFormat() { return format; }
    public Double getMinRating() { return minRating; }
    public Long getChampionUserId() { return championUserId; }
    public void setChampionUserId(Long championUserId) { this.championUserId = championUserId; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getStartedAt() { return startedAt; }
    public void setStartedAt(Instant startedAt) { this.startedAt = startedAt; }
    public Instant getFinishedAt() { return finishedAt; }
    public void setFinishedAt(Instant finishedAt) { this.finishedAt = finishedAt; }

    /** How many rounds a bracket of this size has — 3 for 8 players, up to the final. */
    public int rounds() {
        return Integer.numberOfTrailingZeros(size);
    }
}
