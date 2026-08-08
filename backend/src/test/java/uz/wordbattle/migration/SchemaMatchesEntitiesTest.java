package uz.wordbattle.migration;

import static org.assertj.core.api.Assertions.assertThat;

import java.sql.Connection;
import java.sql.SQLException;
import javax.sql.DataSource;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.junit.jupiter.Testcontainers;
import uz.wordbattle.user.User;
import uz.wordbattle.user.UserRepository;

/**
 * Starts the server the way production starts it: Flyway migrates a real
 * PostgreSQL, then Hibernate is told to {@code validate} what it finds instead
 * of creating it.
 *
 * <p>This is the check the rest of the suite cannot make. On H2 the entities
 * are the schema — {@code ddl-auto: create-drop} builds the tables from them,
 * so they agree by construction. In production a column an entity expects and a
 * migration never added is caught at startup, and the server does not come up
 * at all; the failure lands on a deploy rather than on a test run.
 *
 * <p>Loading the context is the assertion. Everything in the test body is here
 * to prove the context that loaded was really the production combination and
 * not H2 wearing its name.
 */
@SpringBootTest
@Testcontainers(disabledWithoutDocker = true)
class SchemaMatchesEntitiesTest {

    /**
     * src/test/resources/application.yml points the whole suite at H2 with
     * Flyway off, and these override it for this class alone — dynamic
     * properties outrank a file, and the file stays as it is for the 60-odd
     * tests that want the fast in-memory database.
     */
    @DynamicPropertySource
    static void useMigratedPostgres(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", MigrationDatabase.POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", MigrationDatabase.POSTGRES::getUsername);
        registry.add("spring.datasource.password", MigrationDatabase.POSTGRES::getPassword);
        registry.add("spring.datasource.driver-class-name", () -> "org.postgresql.Driver");
        registry.add("spring.jpa.database-platform", () -> "org.hibernate.dialect.PostgreSQLDialect");
        // The pairing this test exists for, copied from the production
        // application.yml: the migrations own the schema, Hibernate only checks
        // it, and the flag that decides what happens to a database Flyway has
        // never seen before is set the same way too.
        registry.add("spring.flyway.enabled", () -> "true");
        registry.add("spring.flyway.baseline-on-migrate", () -> "true");
        registry.add("spring.jpa.hibernate.ddl-auto", () -> "validate");
    }

    @Autowired
    private DataSource dataSource;

    @Autowired
    private UserRepository users;

    @Test
    void everyEntityMatchesTheMigratedSchema() throws SQLException {
        // If the overrides above ever stopped taking effect, the context would
        // still load — on H2, proving nothing. So this comes first.
        try (Connection connection = dataSource.getConnection()) {
            assertThat(connection.getMetaData().getDatabaseProductName()).isEqualTo("PostgreSQL");
        }

        // Hibernate has already compared every entity against the migrated
        // tables by now; reaching this line is that check passing. What is left
        // is the round trip no schema comparison covers.
        User saved = users.save(User.withGoogle("migration-check", "Aziza"));
        assertThat(saved.getId()).isNotNull();

        // The second write goes out as `update ... where id = ? and version = ?`,
        // so it updates a row only if V5's column holds the value Hibernate
        // wrote a moment ago rather than a null or a default the entity never
        // saw.
        saved.setCity("Toshkent");
        users.save(saved);
        assertThat(users.findById(saved.getId()).orElseThrow().getCity()).isEqualTo("Toshkent");
    }
}
