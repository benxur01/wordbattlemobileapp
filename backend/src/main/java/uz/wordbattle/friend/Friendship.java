package uz.wordbattle.friend;

import jakarta.persistence.*;
import java.time.Instant;

/**
 * Stored once per direction, so listing a player's friends never needs an OR
 * over two columns.
 */
@Entity
@Table(name = "friendships", uniqueConstraints = @UniqueConstraint(columnNames = {"user_id", "friend_id"}))
public class Friendship {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Column(name = "friend_id", nullable = false)
    private Long friendId;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt = Instant.now();

    protected Friendship() {}

    public Friendship(Long userId, Long friendId) {
        this.userId = userId;
        this.friendId = friendId;
    }

    public Long getId() { return id; }
    public Long getUserId() { return userId; }
    public Long getFriendId() { return friendId; }
    public Instant getCreatedAt() { return createdAt; }
}
