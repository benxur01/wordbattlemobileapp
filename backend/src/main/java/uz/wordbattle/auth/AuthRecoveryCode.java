package uz.wordbattle.auth;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;

@Entity
@Table(name = "auth_recovery_codes")
public class AuthRecoveryCode {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Column(nullable = false, length = 32)
    private String purpose;

    @Column(nullable = false, length = 320)
    private String email;

    @Column(name = "code_hash", nullable = false, length = 64)
    private String codeHash;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;

    @Column(nullable = false)
    private int attempts;

    protected AuthRecoveryCode() {}

    public AuthRecoveryCode(Long userId, String purpose, String email, String codeHash, Instant now, Instant expiresAt) {
        this.userId = userId;
        this.purpose = purpose;
        this.email = email;
        this.codeHash = codeHash;
        this.createdAt = now;
        this.expiresAt = expiresAt;
        this.attempts = 0;
    }

    public Long getId() { return id; }
    public Long getUserId() { return userId; }
    public String getPurpose() { return purpose; }
    public String getEmail() { return email; }
    public String getCodeHash() { return codeHash; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getExpiresAt() { return expiresAt; }
    public int getAttempts() { return attempts; }

    public void replace(String email, String codeHash, Instant now, Instant expiresAt) {
        this.email = email;
        this.codeHash = codeHash;
        this.createdAt = now;
        this.expiresAt = expiresAt;
        this.attempts = 0;
    }

    public void incrementAttempts() { attempts++; }
}
