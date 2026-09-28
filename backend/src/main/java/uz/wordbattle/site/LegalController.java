package uz.wordbattle.site;

import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import org.springframework.core.io.ClassPathResource;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.util.HtmlUtils;
import uz.wordbattle.config.AppProperties;

/**
 * The privacy policy and the terms of use, as plain pages anyone can open —
 * both stores ask for a URL to each, and the app links to them from the
 * profile screen.
 *
 * <p>The text lives in {@code resources/legal/} with two placeholders, the
 * contact address and the operator's name, filled in from {@code
 * wordbattle.legal}. Both are escaped on the way in: they come from an
 * environment variable, and whatever is in it lands in the middle of an HTML
 * page and a {@code mailto:} attribute. Rendered once, since neither can change
 * while the server runs.
 */
@RestController
public class LegalController {

    private static final String HTML = "text/html;charset=UTF-8";

    private final String privacy;
    private final String terms;

    public LegalController(AppProperties props) {
        Map<String, String> values = Map.of(
                "{{CONTACT_EMAIL}}", HtmlUtils.htmlEscape(props.legal().contactEmail()),
                "{{OPERATOR_NAME}}", HtmlUtils.htmlEscape(props.legal().operatorName()));
        this.privacy = render("legal/privacy.html", values);
        this.terms = render("legal/terms.html", values);
    }

    @GetMapping(value = "/privacy", produces = HTML)
    public String privacy() {
        return privacy;
    }

    @GetMapping(value = "/terms", produces = HTML)
    public String terms() {
        return terms;
    }

    private static String render(String template, Map<String, String> values) {
        String page;
        try (InputStream in = new ClassPathResource(template).getInputStream()) {
            page = new String(in.readAllBytes(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException("Could not read " + template, e);
        }
        for (Map.Entry<String, String> value : values.entrySet()) {
            page = page.replace(value.getKey(), value.getValue());
        }
        return page;
    }
}
