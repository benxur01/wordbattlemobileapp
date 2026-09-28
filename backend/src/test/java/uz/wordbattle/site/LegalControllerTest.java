package uz.wordbattle.site;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

/**
 * The privacy policy and the terms, opened the way a store reviewer opens
 * them: no account, no token.
 *
 * <p>The contact address and the operator's name come from the environment and
 * land in the middle of an HTML page, so they are configured here as markup and
 * have to come back as text.
 */
@SpringBootTest(properties = {
    "wordbattle.legal.contact-email=privacy<script>alert(1)</script>@example.uz",
    "wordbattle.legal.operator-name=\"Sanjar & Co\" MChJ"
})
@AutoConfigureMockMvc
class LegalControllerTest {

    @Autowired
    private MockMvc mvc;

    @Test
    void thePrivacyPolicyIsOpenToAnyoneAndCarriesTheConfiguredContactEscaped() throws Exception {
        String page = page("/privacy");

        assertThat(page).contains("Maxfiylik siyosati");
        assertThat(page).contains("privacy&lt;script&gt;alert(1)&lt;/script&gt;@example.uz");
        assertThat(page).contains("&quot;Sanjar &amp; Co&quot; MChJ");
        assertThat(page).doesNotContain("<script>");
        assertThat(page).doesNotContain("{{");
    }

    @Test
    void theTermsAreOpenToAnyoneAndCarryTheConfiguredContactEscaped() throws Exception {
        String page = page("/terms");

        assertThat(page).contains("Foydalanish shartlari");
        assertThat(page).contains("mailto:privacy&lt;script&gt;alert(1)&lt;/script&gt;@example.uz");
        assertThat(page).contains("&quot;Sanjar &amp; Co&quot; MChJ");
        assertThat(page).doesNotContain("<script>");
        assertThat(page).doesNotContain("{{");
    }

    private String page(String path) throws Exception {
        return mvc.perform(get(path))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.TEXT_HTML))
                .andExpect(content().encoding(StandardCharsets.UTF_8))
                .andReturn()
                .getResponse()
                .getContentAsString(StandardCharsets.UTF_8);
    }
}
