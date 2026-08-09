package uz.wordbattle.migration;

import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import java.io.IOException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.testcontainers.DockerClientFactory;
import org.testcontainers.containers.PostgreSQLContainer;

/**
 * The one real PostgreSQL the migration tests share.
 *
 * <p>Started from a static initialiser rather than from a {@code @Container}
 * field, because {@code @DynamicPropertySource} reads the JDBC URL while Spring
 * is building the context — earlier than the Testcontainers extension would
 * have got round to starting a managed container. Class initialisation happens
 * on the first touch from whichever test runs first, and only once, so both
 * test classes get the same database and the suite pays for one start.
 *
 * <p>Two ways to get one, and the tests do not care which they got:
 *
 * <ul>
 *   <li><b>Testcontainers</b> when a Docker daemon is there. Preferred, because
 *       it runs the very image {@code docker-compose.yml} runs. Its Ryuk
 *       sidecar removes the container when the JVM that asked for it exits.
 *   <li><b>Embedded PostgreSQL</b> otherwise: the same major version, unpacked
 *       from a Maven artifact and run as a plain child process. No daemon, no
 *       root, nothing to install.
 * </ul>
 *
 * <p>The fallback is the point. These tests used to carry
 * {@code @Testcontainers(disabledWithoutDocker = true)} and were the only check
 * that the Flyway migrations and the JPA entities agree — the rest of the suite
 * runs on H2 with {@code ddl-auto: create-drop}, where the entities <em>are</em>
 * the schema and agree by construction. On a machine without Docker they
 * therefore reported themselves skipped, which in a wall of green output reads
 * exactly like a pass, and the migrations went to production having never once
 * been run. Now the tests run everywhere, and a platform with neither Docker
 * nor a binary fails loudly instead of going quiet.
 */
final class MigrationDatabase {

    private static final Logger log = LoggerFactory.getLogger(MigrationDatabase.class);

    /** The image docker-compose.yml runs, so the tests fail where production would. */
    private static final String IMAGE = "postgres:16-alpine";

    private record Handle(String jdbcUrl, String username, String password) {}

    private static final Handle HANDLE = start();

    static String jdbcUrl() {
        return HANDLE.jdbcUrl();
    }

    static String username() {
        return HANDLE.username();
    }

    static String password() {
        return HANDLE.password();
    }

    private static Handle start() {
        if (dockerAvailable()) {
            PostgreSQLContainer<?> container = new PostgreSQLContainer<>(IMAGE);
            container.start();
            log.info("Migration tests are using Testcontainers ({})", IMAGE);
            return new Handle(container.getJdbcUrl(), container.getUsername(), container.getPassword());
        }

        try {
            EmbeddedPostgres postgres = EmbeddedPostgres.builder().start();
            // Testcontainers has Ryuk; this one has to clear up after itself.
            Runtime.getRuntime().addShutdownHook(new Thread(() -> close(postgres), "embedded-postgres-stop"));
            log.info("No Docker daemon — migration tests are using an embedded PostgreSQL on port {}",
                    postgres.getPort());
            return new Handle(postgres.getJdbcUrl("postgres", "postgres"), "postgres", "postgres");
        } catch (IOException | RuntimeException e) {
            throw new IllegalStateException(
                    "Migratsiya testlari uchun haqiqiy PostgreSQL kerak, lekin na Docker, na bu platforma uchun "
                            + "o'rnatilgan server topildi. Docker'ni ishga tushiring va qaytadan urinib ko'ring.",
                    e);
        }
    }

    private static boolean dockerAvailable() {
        try {
            return DockerClientFactory.instance().isDockerAvailable();
        } catch (RuntimeException e) {
            // A half-configured daemon (a stale DOCKER_HOST, a socket nothing
            // is listening on) must send us to the fallback, not fail the run.
            log.debug("Docker probe failed, falling back to an embedded server", e);
            return false;
        }
    }

    private static void close(EmbeddedPostgres postgres) {
        try {
            postgres.close();
        } catch (IOException e) {
            log.debug("Embedded PostgreSQL did not shut down cleanly", e);
        }
    }

    private MigrationDatabase() {}
}
