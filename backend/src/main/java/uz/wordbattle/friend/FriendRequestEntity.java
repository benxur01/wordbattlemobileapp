package uz.wordbattle.friend;

import jakarta.persistence.*;
import java.time.Instant;

@Entity
@Table(name = "friend_requests")
public class FriendRequestEntity {

    public enum Status { PENDING, ACCEPTED, DECLINED }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * Optimistic lock, for the same reason {@code User} carries one: two calls
     * settle this row at once and each decides what to write from what it read.
     * Answering a request is read-check-write — is it still pending, then mark
     * it — and a player double-tapping "Qabul qilish", or tapping accept while
     * the decline underneath their thumb is still in flight, sends both calls
     * off together. Both used to see PENDING, and both went on: the second
     * accept reached the friendship insert the first had already made and came
     * back as a 500 for pressing a button twice, and accept-against-decline
     * could leave the row DECLINED with the friendship the accept created
     * standing beside it, a friend nobody had agreed to.
     *
     * <p>The version settles it in the database, which is the only place both
     * calls meet: the loser's update matches no row, is refused, and its whole
     * transaction — the friendship edges included — is rolled back. See {@code
     * FriendService.resolve}, which flushes on the spot so the refusal arrives
     * while there is still a call frame to answer it in.
     *
     * <p>Primitive on purpose, as on {@code User}: Spring Data decides "new or
     * detached" from the id when the version is one, which is the behaviour
     * {@code sendRequest} already relies on.
     */
    @Version
    @Column(name = "version", nullable = false)
    private long version;

    @Column(name = "from_user_id", nullable = false)
    private Long fromUserId;

    @Column(name = "to_user_id", nullable = false)
    private Long toUserId;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private Status status = Status.PENDING;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt = Instant.now();

    @Column(name = "resolved_at")
    private Instant resolvedAt;

    protected FriendRequestEntity() {}

    public FriendRequestEntity(Long fromUserId, Long toUserId) {
        this.fromUserId = fromUserId;
        this.toUserId = toUserId;
    }

    public void resolve(Status status) {
        this.status = status;
        this.resolvedAt = Instant.now();
    }

    public Long getId() { return id; }
    public Long getFromUserId() { return fromUserId; }
    public Long getToUserId() { return toUserId; }
    public Status getStatus() { return status; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getResolvedAt() { return resolvedAt; }
}
