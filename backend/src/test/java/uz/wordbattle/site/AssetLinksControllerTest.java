package uz.wordbattle.site;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.context.properties.bind.Binder;
import org.springframework.boot.context.properties.source.ConfigurationPropertySources;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.core.env.MapPropertySource;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import uz.wordbattle.config.AppProperties;

/**
 * The Digital Asset Links file, which Android's verifier fetches with no token
 * and reads as a claim: whatever it names, it says the app is allowed to open
 * this host's links. So it names nothing until a real fingerprint is given,
 * and exactly the given ones after.
 */
@SpringBootTest
@AutoConfigureMockMvc
class AssetLinksControllerTest {

    @Autowired
    private MockMvc mvc;

    @Autowired
    private ObjectMapper mapper;

    @Test
    void withNoFingerprintConfiguredTheFileIsAnEmptyListAnyoneCanFetch() throws Exception {
        mvc.perform(get("/.well-known/assetlinks.json"))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
                .andExpect(content().json("[]", true));
    }

    @Test
    void configuredFingerprintsBecomeOneStatementForTheApp() throws Exception {
        AppProperties props = new Binder(ConfigurationPropertySources.from(new MapPropertySource(
                        "test",
                        Map.<String, Object>of(
                                "wordbattle.app-links.sha256-fingerprints", "14:6d:e9:83:c5 , AB:CD:EF:01"))))
                .bindOrCreate("wordbattle", AppProperties.class);

        JsonNode file = mapper.readTree(mapper.writeValueAsString(new AssetLinksController(props).assetLinks()));

        assertThat(file).hasSize(1);
        JsonNode statement = file.get(0);
        assertThat(statement.get("relation").get(0).asText()).isEqualTo("delegate_permission/common.handle_all_urls");
        JsonNode target = statement.get("target");
        assertThat(target.get("namespace").asText()).isEqualTo("android_app");
        assertThat(target.get("package_name").asText()).isEqualTo("com.wordbattle.word_battle");
        // Trimmed and upper-cased, the form keytool prints and Google documents.
        assertThat(target.get("sha256_cert_fingerprints"))
                .extracting(JsonNode::asText)
                .containsExactly("14:6D:E9:83:C5", "AB:CD:EF:01");
    }
}
