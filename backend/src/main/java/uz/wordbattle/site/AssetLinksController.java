package uz.wordbattle.site;

import com.fasterxml.jackson.annotation.JsonProperty;
import java.util.List;
import java.util.Locale;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import uz.wordbattle.config.AppProperties;

/**
 * The Digital Asset Links statement Android fetches before it lets the app
 * open a shared tournament link ({@code https://<host>/t/<id>}) itself instead
 * of handing it to the browser.
 *
 * <p>Built from configuration rather than shipped as a file, because the one
 * value that matters — the fingerprint of the certificate the release is
 * signed with — belongs to whoever holds the release key, not to the
 * repository. A committed file carried a placeholder that a verifier would
 * have read as a claim, on a domain that did not exist yet.
 *
 * <p>With nothing configured the answer is an empty list: a well-formed file
 * that verifies no app, which is the truth until a key and a domain exist.
 * {@code SecurityConfig} leaves {@code /.well-known/**} open, since the
 * verifier carries no token.
 */
@RestController
public class AssetLinksController {

    /** The Android {@code applicationId} — see android/app/build.gradle.kts. */
    static final String PACKAGE_NAME = "com.wordbattle.word_battle";

    public record Statement(List<String> relation, Target target) {}

    public record Target(
            String namespace,
            @JsonProperty("package_name") String packageName,
            @JsonProperty("sha256_cert_fingerprints") List<String> sha256CertFingerprints) {}

    private final List<Statement> statements;

    public AssetLinksController(AppProperties props) {
        // keytool prints the fingerprint in upper case, and that is the form
        // Google's own examples use; a pasted lower-case one is not worth a
        // failed verification to find out whether case matters.
        List<String> fingerprints = props.appLinks().sha256Fingerprints().stream()
                .map(String::strip)
                .filter(fingerprint -> !fingerprint.isEmpty())
                .map(fingerprint -> fingerprint.toUpperCase(Locale.ROOT))
                .toList();
        this.statements = fingerprints.isEmpty()
                ? List.of()
                : List.of(new Statement(
                        List.of("delegate_permission/common.handle_all_urls"),
                        new Target("android_app", PACKAGE_NAME, fingerprints)));
    }

    @GetMapping(value = "/.well-known/assetlinks.json", produces = MediaType.APPLICATION_JSON_VALUE)
    public List<Statement> assetLinks() {
        return statements;
    }
}
