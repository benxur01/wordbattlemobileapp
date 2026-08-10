package uz.wordbattle.config;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.lang.reflect.RecordComponent;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.TreeMap;
import java.util.TreeSet;
import org.junit.jupiter.api.Test;
import org.springframework.boot.context.properties.bind.Binder;
import org.springframework.boot.context.properties.bind.PropertySourcesPlaceholdersResolver;
import org.springframework.boot.context.properties.source.ConfigurationPropertySources;
import org.springframework.boot.env.YamlPropertySourceLoader;
import org.springframework.core.env.EnumerablePropertySource;
import org.springframework.core.env.MapPropertySource;
import org.springframework.core.env.PropertySource;
import org.springframework.core.io.FileSystemResource;

/**
 * The configuration the server ships with, held against the defaults baked into
 * {@link AppProperties}.
 *
 * <p>The two have to say the same thing because of a hole nobody meant to dig.
 * {@code src/test/resources/application.yml} does not add to the shipped file —
 * it replaces it outright. So the suite runs on whatever that test file happens
 * to restate (a database, a secret, dev login) and on the record's
 * {@code @DefaultValue} annotations for everything it does not, which is very
 * nearly every game rule there is. It surfaced by accident on 2026-08-09:
 * someone put {@code turn-seconds: 99} in the shipped file and the test
 * asserting 15 went on passing.
 *
 * <p>What that let through is the point. A rule could be retuned in the file
 * that ships and no test would notice; a fix could be written into the yml and
 * never once be exercised. Both nearly happened to the matchmaking retune the
 * same afternoon — the five queue numbers were corrected in the yml while every
 * socket test carried on queueing players under the schedule that had stranded
 * them, and {@code MatchmakingBandTest} had to grow a guard of its own to catch
 * it. This is that guard, generalised: the annotations are not a fallback
 * nobody meets, they are what the suite plays on, so they are held to the yml
 * for every property rather than for the one section that got caught.
 *
 * <p>The shipped file is read off disk rather than copied into a constant here,
 * because a copy is precisely the thing that would drift while the test kept
 * passing.
 */
class ShippedConfigurationTest {

    /** What the server ships. Relative to the module, which is where Maven runs. */
    private static final Path SHIPPED_YAML = Path.of("src/main/resources/application.yml");

    /**
     * The two properties the shipped file and the annotation are meant to
     * disagree on. Both are exempted by name and not by loosening the
     * comparison, so adding a third takes a deliberate edit here.
     *
     * <p>{@code jwt.secret} has no {@code @DefaultValue} at all, on purpose: a
     * default secret is a secret every reader of this repository can already
     * sign tokens with, so the server refuses to start without a real one. The
     * yml spells the same refusal as {@code ${JWT_SECRET:}} — an empty string
     * when nothing is exported. {@code JwtService} treats null and blank
     * identically, so the two are one decision written twice, and comparing
     * them would only compare the spelling.
     *
     * <p>{@code google.web-client-id} is a genuine difference and worth being
     * uneasy about. The yml carries the project's real web client id, because
     * an empty one disables Google sign-in silently and the first player to try
     * it fails for a reason nothing in the logs points at; a client id is not a
     * secret, it ships inside every build. The annotation stays empty so a
     * context that binds no {@code wordbattle.google} block at all reports
     * {@code configured() == false} rather than claiming a Google project it
     * was never given. Same field, two questions.
     *
     * <p>{@code cors.allowed-origins} is deliberately <em>not</em> here. It is
     * environment-shaped in the sense that a deployment may set it, but the
     * value the file ships with is the empty list and so is the annotation's,
     * and keeping it in the comparison is what stops an origin being hard-coded
     * into the file: origins belong in {@code CORS_ALLOWED_ORIGINS}, not here.
     */
    private static final Set<String> DELIBERATELY_DIFFERENT =
            Set.of("wordbattle.jwt.secret", "wordbattle.google.web-client-id");

    /**
     * Change a game rule in one of the two files and this is what fails.
     *
     * <p>It walks the record rather than listing properties, so a tunable added
     * later is covered the day it is added and not the day somebody remembers
     * this file exists.
     */
    @Test
    void everyShippedValueMatchesItsBuiltInDefault() {
        Map<String, Object> shipped = flatten("wordbattle", bindShipped());
        Map<String, Object> builtIn = flatten("wordbattle", bindBuiltInDefaults());

        // Same record on both sides, so the key sets match by construction and
        // only the values can part company.
        Map<String, String> drift = new TreeMap<>();
        builtIn.forEach((property, builtInValue) -> {
            if (DELIBERATELY_DIFFERENT.contains(property)) return;
            Object shippedValue = shipped.get(property);
            if (!Objects.equals(shippedValue, builtInValue)) {
                drift.put(property, "application.yml says %s, @DefaultValue says %s".formatted(shippedValue, builtInValue));
            }
        });

        assertThat(drift)
                .as("%s and the @DefaultValue annotations in AppProperties have parted company. "
                        + "The suite plays on the annotations, so whatever is listed here is a rule the "
                        + "tests are proving at a value production does not use. Change both files, or "
                        + "add the property to DELIBERATELY_DIFFERENT with the reason.", SHIPPED_YAML)
                .isEmpty();
    }

    /**
     * A key the record has no home for. Binding ignores what it does not
     * recognise, so {@code turn-second: 20} — one letter short — is dropped in
     * silence: the game keeps its old value, the drift check above sees two
     * files that agree, and whoever made the edit has every reason to believe
     * it took. That is the same failure mode as the shadowing, one level down,
     * and it costs one assertion to close.
     */
    @Test
    void everyKeyInTheShippedFileIsAPropertyThatExists() {
        Set<String> known = flatten("wordbattle", bindBuiltInDefaults()).keySet();

        assertThat(shippedKeys())
                .as("no field in AppProperties answers to this — check the spelling, "
                        + "because binding drops unknown keys without a word")
                .isSubsetOf(known);
    }

    // --------------------------------------------------------------- helpers

    /** The shipped file as the game would read it, with no environment set. */
    private AppProperties bindShipped() {
        List<PropertySource<?>> yaml = loadShipped();
        return new Binder(
                        ConfigurationPropertySources.from(yaml),
                        // Placeholders resolve against the file and nothing else. A
                        // developer with JWT_SECRET or DUEL_RARE_LETTERS exported must
                        // not get a different answer from CI, and what is being checked
                        // is what the file ships with — the fallback after the colon —
                        // not what any one machine overrides it to.
                        new PropertySourcesPlaceholdersResolver(yaml))
                .bindOrCreate("wordbattle", AppProperties.class);
    }

    /** The record's own defaults, bound from nothing at all. */
    private AppProperties bindBuiltInDefaults() {
        return new Binder(ConfigurationPropertySources.from(new MapPropertySource("none", Map.of())))
                .bindOrCreate("wordbattle", AppProperties.class);
    }

    /**
     * Every {@code wordbattle.*} key the shipped file actually writes. List
     * entries arrive indexed ({@code allowed-origins[0]}), which names the same
     * property, so the index is dropped before the name is checked.
     */
    private Set<String> shippedKeys() {
        Set<String> keys = new TreeSet<>();
        for (PropertySource<?> source : loadShipped()) {
            if (!(source instanceof EnumerablePropertySource<?> enumerable)) continue;
            for (String name : enumerable.getPropertyNames()) {
                if (name.startsWith("wordbattle.")) keys.add(name.replaceAll("\\[\\d+]", ""));
            }
        }
        return keys;
    }

    private List<PropertySource<?>> loadShipped() {
        assertThat(Files.exists(SHIPPED_YAML))
                .as("%s (run from the backend module, as Maven does)", SHIPPED_YAML.toAbsolutePath())
                .isTrue();
        try {
            return new YamlPropertySourceLoader().load("shipped", new FileSystemResource(SHIPPED_YAML));
        } catch (IOException e) {
            throw new AssertionError("Could not read " + SHIPPED_YAML, e);
        }
    }

    /**
     * A record laid out flat as the property names it binds from, so a mismatch
     * can be reported as {@code wordbattle.duel.turn-seconds} rather than as two
     * whole records the reader has to compare by eye.
     */
    private static Map<String, Object> flatten(String prefix, Object record) {
        Map<String, Object> flat = new TreeMap<>();
        for (RecordComponent component : record.getClass().getRecordComponents()) {
            String property = prefix + "." + kebabCase(component.getName());
            Object value = read(component, record);
            if (value != null && value.getClass().isRecord()) {
                flat.putAll(flatten(property, value));
            } else {
                flat.put(property, value);
            }
        }
        return flat;
    }

    private static Object read(RecordComponent component, Object owner) {
        try {
            return component.getAccessor().invoke(owner);
        } catch (ReflectiveOperationException e) {
            throw new AssertionError("Could not read " + component.getName(), e);
        }
    }

    /** {@code botFallbackSeconds} as the yml writes it: {@code bot-fallback-seconds}. */
    private static String kebabCase(String camelCase) {
        StringBuilder kebab = new StringBuilder();
        for (char c : camelCase.toCharArray()) {
            if (Character.isUpperCase(c)) {
                kebab.append('-').append(Character.toLowerCase(c));
            } else {
                kebab.append(c);
            }
        }
        return kebab.toString();
    }
}
