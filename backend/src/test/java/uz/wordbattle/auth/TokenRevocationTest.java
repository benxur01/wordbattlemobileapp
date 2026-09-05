package uz.wordbattle.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Duration;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import uz.wordbattle.config.AppProperties;
import uz.wordbattle.user.User;
import uz.wordbattle.user.UserRepository;

/**
 * Signing out, from the server's side of it.
 *
 * <p>The token used to outlive the sign-out entirely: the app forgot it and the
 * server went on honouring it for the rest of its 30-day life, so a copy of it
 * — off an old device backup, out of a proxy log, from a phone that changed
 * hands — still had the account for up to a month after the player believed
 * they had left it. These tests are the proof that pressing "Chiqish" now ends
 * the token rather than only hiding it.
 *
 * <p>The socket side of the same question is {@link RevokedTokenSocketTest};
 * between them they cover both doors a token can be presented at.
 */
@SpringBootTest
@AutoConfigureMockMvc
class TokenRevocationTest {

    @Autowired
    private MockMvc mvc;

    @Autowired
    private ObjectMapper mapper;

    @Autowired
    private AppProperties props;

    @Autowired
    private UserRepository users;

    @Autowired
    private JwtService jwt;

    @Test
    void signingOutStopsTheTokenThatDidIt() throws Exception {
        String token = login("Sardor");
        mvc.perform(get("/api/users/me").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk());

        mvc.perform(post("/api/auth/logout").header("Authorization", "Bearer " + token))
                .andExpect(status().isNoContent());

        // Immediately, not when the TTL runs out a month from now.
        mvc.perform(get("/api/users/me").header("Authorization", "Bearer " + token))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("unauthorized"));
        // Every authenticated endpoint, not only the one the app happens to
        // call first on the way back in.
        mvc.perform(get("/api/friends").header("Authorization", "Bearer " + token))
                .andExpect(status().isUnauthorized());
        mvc.perform(get("/api/users/me/profile").header("Authorization", "Bearer " + token))
                .andExpect(status().isUnauthorized());
    }

    /**
     * Signing out must not lock the player out of their own account — the next
     * token for the same row has to work.
     *
     * <p>Dev login cannot show this: it mints a brand-new throwaway account
     * every time and would prove nothing about the account that just signed
     * out. So the token is minted the way {@code AuthController} mints one for
     * a returning Google player — from the row, read back after the sign-out —
     * which is also what pins down that the counter the sign-out moved is
     * visible to the code that stamps the next token.
     */
    @Test
    void theNextSignInOfTheSameAccountWorks() throws Exception {
        String token = login("Kamola");
        long id = userId(token);

        mvc.perform(post("/api/auth/logout").header("Authorization", "Bearer " + token))
                .andExpect(status().isNoContent());

        String fresh = issueFor(id);
        assertThat(fresh).isNotEqualTo(token);
        mvc.perform(get("/api/users/me").header("Authorization", "Bearer " + fresh))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.displayName").value("Kamola"));

        // And the dead one stays dead: a new sign-in revives the account, not
        // every token ever issued for it.
        mvc.perform(get("/api/users/me").header("Authorization", "Bearer " + token))
                .andExpect(status().isUnauthorized());
    }

    /**
     * Two sign-ins of the same account, then one sign-out. Both tokens die,
     * because the counter belongs to the account rather than to a token — the
     * trade this design accepts, and the safer half of it.
     */
    @Test
    void signingOutOnOneDeviceEndsTheOtherDevicesToo() throws Exception {
        String phone = login("Nodira");
        long id = userId(phone);
        String tablet = issueFor(id);
        mvc.perform(get("/api/users/me").header("Authorization", "Bearer " + tablet))
                .andExpect(status().isOk());

        mvc.perform(post("/api/auth/logout").header("Authorization", "Bearer " + phone))
                .andExpect(status().isNoContent());

        mvc.perform(get("/api/users/me").header("Authorization", "Bearer " + tablet))
                .andExpect(status().isUnauthorized());
    }

    /**
     * Deleting the account revokes with it, and needs no step of its own: the
     * generation is read only for a row that is not marked deleted, so an
     * erased account has none and its tokens name nobody.
     *
     * <p>It answers 401 rather than the 404 the endpoints behind it used to
     * produce — the token is refused at the door now, and 401 is the answer the
     * app is already watching for to send the player back to onboarding.
     */
    @Test
    void deletingTheAccountRevokesEveryTokenForIt() throws Exception {
        String token = login("Rustam");
        long id = userId(token);
        String second = issueFor(id);

        mvc.perform(delete("/api/users/me").header("Authorization", "Bearer " + token))
                .andExpect(status().isNoContent());

        mvc.perform(get("/api/users/me").header("Authorization", "Bearer " + token))
                .andExpect(status().isUnauthorized());
        mvc.perform(get("/api/users/me").header("Authorization", "Bearer " + second))
                .andExpect(status().isUnauthorized());
    }

    /**
     * The cases that were already refused have to stay exactly as they were —
     * a clean 401 and nothing else. A revocation check that turned a garbled
     * token into a 500 would have made the app's "log in again" path
     * unreachable for the most ordinary failure there is.
     */
    @Test
    void anExpiredOrGarbledTokenIsStillAPlainUnauthorized() throws Exception {
        mvc.perform(get("/api/users/me").header("Authorization", "Bearer not-a-token"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("unauthorized"));
        mvc.perform(get("/api/users/me").header("Authorization", "Bearer "))
                .andExpect(status().isUnauthorized());

        // Properly signed, properly stamped, and a second past its expiry: the
        // one failure the revocation check must never be reached for, since the
        // account behind it is perfectly alive.
        String expired = expiredTokenFor(userId(login("Malika")));
        mvc.perform(get("/api/users/me").header("Authorization", "Bearer " + expired))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("unauthorized"));
    }

    /**
     * A write to the row that was already in flight when the player signed out.
     * The one this is really about is a duel settling: it reads the player,
     * adds its rating and statistics to what it read, and writes every column
     * back — so a mapped {@code token_generation} would have carried the value
     * from before the sign-out over the top of it and quietly brought the dead
     * token back to life. The column is {@code updatable = false} for exactly
     * this, and a save of a stale entity is the deterministic way to say so.
     */
    @Test
    void aWriteThatStartedBeforeTheSignOutCannotUndoIt() throws Exception {
        String token = login("Feruza");
        long id = userId(token);
        User loadedBeforeTheSignOut = users.findById(id).orElseThrow();

        mvc.perform(post("/api/auth/logout").header("Authorization", "Bearer " + token))
                .andExpect(status().isNoContent());

        loadedBeforeTheSignOut.setCity("Toshkent");
        users.saveAndFlush(loadedBeforeTheSignOut);

        assertThat(users.currentFor(id)).contains(1L);
        mvc.perform(get("/api/users/me").header("Authorization", "Bearer " + token))
                .andExpect(status().isUnauthorized());
    }

    /**
     * The app calls this on its way out and does not wait to be told it may.
     * A caller with no token, or one signing out a second time, gets the same
     * quiet 204 — there is nothing to revoke and nothing worth telling them.
     */
    @Test
    void signingOutWithoutAUsableTokenIsAcceptedAndDoesNothing() throws Exception {
        mvc.perform(post("/api/auth/logout")).andExpect(status().isNoContent());
        mvc.perform(post("/api/auth/logout").header("Authorization", "Bearer not-a-token"))
                .andExpect(status().isNoContent());

        String token = login("Jahongir");
        long id = userId(token);
        mvc.perform(post("/api/auth/logout").header("Authorization", "Bearer " + token))
                .andExpect(status().isNoContent());
        mvc.perform(post("/api/auth/logout").header("Authorization", "Bearer " + token))
                .andExpect(status().isNoContent());

        // Moved once, by the one call that was authenticated. The endpoint sits
        // on a permit-all path, so the null check is the only thing between an
        // anonymous POST and somebody else's session; a counter at 2 would mean
        // a refused token had ended a live one.
        assertThat(users.currentFor(id)).contains(1L);
    }

    // --------------------------------------------------------------- helpers

    private String login(String name) throws Exception {
        String body = mvc.perform(post("/api/auth/dev")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"displayName\":\"" + name + "\"}"))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();
        return mapper.readTree(body).get("token").asText();
    }

    private long userId(String token) throws Exception {
        String body = mvc.perform(get("/api/users/me").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();
        return mapper.readTree(body).get("id").asLong();
    }

    /** A second sign-in of an existing account, as {@code AuthController} does it. */
    private String issueFor(long id) {
        User user = users.findById(id).orElseThrow();
        return jwt.issue(user.getId(), user.getTokenGeneration());
    }

    /**
     * The same secret, issuer and account as a real token, and a lifetime that
     * ended before it was handed over. Only the TTL is changed, so the token is
     * refused for being expired and for no other reason.
     */
    private String expiredTokenFor(long id) {
        AppProperties expiringInThePast = new AppProperties(
                new AppProperties.Jwt(props.jwt().secret(), Duration.ofSeconds(-1), props.jwt().issuer()),
                props.google(),
                props.duel(),
                props.matchmaking(),
                props.rating(),
                props.cors(),
                props.limits(),
                props.admin(),
                props.tournament(),
                props.timeZone(),
                props.devLoginEnabled());
        return new JwtService(expiringInThePast, users).issue(id, users.currentFor(id).orElseThrow());
    }
}
