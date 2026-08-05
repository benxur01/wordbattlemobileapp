package uz.wordbattle.user;

import jakarta.persistence.*;
import java.io.Serializable;
import java.time.Instant;
import java.util.Objects;

@Entity
@Table(name = "user_words")
@IdClass(UserWord.Key.class)
public class UserWord {

    /** Composite key: a player learns a given word once. */
    public static class Key implements Serializable {
        private Long userId;
        private String word;

        public Key() {}

        public Key(Long userId, String word) {
            this.userId = userId;
            this.word = word;
        }

        @Override
        public boolean equals(Object o) {
            if (this == o) return true;
            if (!(o instanceof Key key)) return false;
            return Objects.equals(userId, key.userId) && Objects.equals(word, key.word);
        }

        @Override
        public int hashCode() {
            return Objects.hash(userId, word);
        }
    }

    @Id
    @Column(name = "user_id")
    private Long userId;

    @Id
    @Column(name = "word", length = 32)
    private String word;

    @Column(name = "first_used_at", nullable = false)
    private Instant firstUsedAt = Instant.now();

    protected UserWord() {}

    public UserWord(Long userId, String word) {
        this.userId = userId;
        this.word = word;
    }

    public Long getUserId() { return userId; }
    public String getWord() { return word; }
    public Instant getFirstUsedAt() { return firstUsedAt; }
}
