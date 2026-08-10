package uz.wordbattle.auth;

import java.util.Optional;

/**
 * The one question {@link JwtService} has to ask the database: which generation
 * of tokens does this account currently accept?
 *
 * <p>An interface rather than the repository itself, in the same spirit as
 * {@code AccountDeletionService.SessionEnder}: the token code stays a question
 * about the token, and its unit test can answer it without a database behind
 * it.
 *
 * <p>Empty means there is no account for a token to belong to — the row is
 * gone, or it has been deleted and all that is left is the anonymous shell an
 * old match points at. Both are "this token authenticates nobody", which is why
 * deleting an account needs no revocation step of its own.
 */
public interface TokenGenerations {

    Optional<Long> currentFor(Long userId);
}
