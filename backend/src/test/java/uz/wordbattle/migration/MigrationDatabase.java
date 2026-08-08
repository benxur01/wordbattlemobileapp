package uz.wordbattle.migration;

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
 * <p>Nothing stops it: Testcontainers' Ryuk sidecar removes the container when
 * the JVM that asked for it exits.
 *
 * <p>Every test class that reaches in here must carry
 * {@code @Testcontainers(disabledWithoutDocker = true)}. That condition is
 * evaluated before anything touches this class, which is what keeps a machine
 * with no Docker daemon skipping the tests instead of failing them.
 */
final class MigrationDatabase {

    /** The image docker-compose.yml runs, so the tests fail where production would. */
    static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:16-alpine");

    static {
        POSTGRES.start();
    }

    private MigrationDatabase() {}
}
