package uz.wordbattle.user;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

/**
 * What a password has to be to open an account, checked through the route the
 * app calls rather than against {@code UserService} directly — the rule is only
 * worth anything if the refusal reaches the phone as a code the sign-up screen
 * can show, and both of these are raised where the nickname rules are.
 */
@SpringBootTest
@AutoConfigureMockMvc
class PasswordRegistrationTest {

    @Autowired
    private MockMvc mvc;

    private ResultActions register(String nickname, String password) throws Exception {
        return mvc.perform(post("/api/auth/register")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"nickname\":\"" + nickname + "\",\"password\":\"" + password + "\"}"));
    }

    /**
     * The two the length rule let through on its own, and the reason it was not
     * a rule: both are six characters and both are near the top of every
     * guessing list there is.
     */
    @Test
    void refusesASixCharacterPasswordWithNothingInItButOneKind() throws Exception {
        register("parol_a", "111111")
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("password_too_simple"));

        register("parol_b", "aaaaaa")
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("password_too_simple"));
    }

    /** The older rule, still the first one asked. */
    @Test
    void refusesAPasswordShorterThanSix() throws Exception {
        register("parol_c", "ab12")
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("password_too_short"));
    }

    @Test
    void acceptsALetterAndADigitAndSignsBackInWithIt() throws Exception {
        register("parol_d", "jasur07").andExpect(status().isOk()).andExpect(jsonPath("$.token").isNotEmpty());

        mvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nickname\":\"parol_d\",\"password\":\"jasur07\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.user.nickname").value("parol_d"));
    }
}
