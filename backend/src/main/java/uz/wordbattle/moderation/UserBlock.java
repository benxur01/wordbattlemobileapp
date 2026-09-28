package uz.wordbattle.moderation;

import jakarta.persistence.*;
import java.io.Serializable;
import java.time.Instant;
import java.util.Objects;

/**
 * One player having blocked another. Stored once, in the blocker's direction,
 * but read in both: a block stands between the two players whichever of them
 * placed it — see {@link BlockService}.
 */
@Entity
@Table(name = "user_blocks")
@IdClass(UserBlock.Key.class)
public class UserBlock {

    /** The table's primary key: the pair itself. */
    public static class Key implements Serializable {

        private Long blockerId;
        private Long blockedId;

        protected Key() {}

        public Key(Long blockerId, Long blockedId) {
            this.blockerId = blockerId;
            this.blockedId = blockedId;
        }

        @Override
        public boolean equals(Object other) {
            return other instanceof Key key
                    && Objects.equals(blockerId, key.blockerId)
                    && Objects.equals(blockedId, key.blockedId);
        }

        @Override
        public int hashCode() {
            return Objects.hash(blockerId, blockedId);
        }
    }

    @Id
    @Column(name = "blocker_id", nullable = false)
    private Long blockerId;

    @Id
    @Column(name = "blocked_id", nullable = false)
    private Long blockedId;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt = Instant.now();

    protected UserBlock() {}

    public UserBlock(Long blockerId, Long blockedId) {
        this.blockerId = blockerId;
        this.blockedId = blockedId;
    }

    public Long getBlockerId() { return blockerId; }
    public Long getBlockedId() { return blockedId; }
    public Instant getCreatedAt() { return createdAt; }
}
