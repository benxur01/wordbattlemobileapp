package uz.wordbattle.migration;

import static org.assertj.core.api.Assertions.assertThat;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.configuration.FluentConfiguration;
import org.flywaydb.core.api.output.MigrateResult;
import org.junit.jupiter.api.Test;

/**
 * Runs {@code db/migration} against a real PostgreSQL.
 *
 * <p>The rest of the suite is fast because it runs on H2 with {@code
 * ddl-auto: create-drop}, which builds the schema out of the entities and never
 * opens a migration file. Production does the opposite — Flyway builds the
 * schema and Hibernate only checks it — so without this test the migrations
 * would first run on the production database, and a migration that fails takes
 * the whole server down with it rather than one endpoint.
 *
 * <p>Two paths get there, and they break differently: a fresh install replays
 * the whole chain into an empty schema, while an upgrade applies the new
 * migrations to a database that already holds rows. {@code V3} dropping a
 * column and {@code V5} adding a {@code not null} one only mean anything on the
 * second path.
 *
 * <p>Each test owns a schema of its own inside the shared database, so they
 * neither see each other's tables nor the one {@link SchemaMatchesEntitiesTest}
 * boots the application against.
 */
class MigrationChainTest {

    /**
     * A fresh install, migrated with the {@code baseline-on-migrate: true}
     * production runs with. The flag is harmless only because the schema is
     * empty: aimed at a schema that already holds tables it adopts that schema
     * at version 1 and skips {@code V1} entirely, which is why the applied
     * versions are worth asserting rather than only the count.
     */
    @Test
    void anEmptySchemaGetsEveryMigrationInOrder() throws SQLException {
        MigrateResult result = migrate("fresh", null);

        assertThat(result.migrationsExecuted).isEqualTo(7);
        assertThat(query(
                        "fresh",
                        "select version from flyway_schema_history where type = 'SQL' order by installed_rank"))
                .containsExactly("1", "2", "3", "4", "5", "6", "7");
        // Two row types are expected: the SQL migrations, and the rank-0 row
        // Flyway writes to record that it created the schema itself. A BASELINE
        // row is the one that must never appear — it marks a migration applied
        // without being run, and is the only way this test passes while the
        // schema is wrong.
        assertThat(query("fresh", "select type from flyway_schema_history"))
                .containsOnly("SCHEMA", "SQL")
                .doesNotContain("BASELINE");

        assertThat(tables("fresh"))
                .containsExactlyInAnyOrder(
                        "flyway_schema_history",
                        "users",
                        "friendships",
                        "friend_requests",
                        "matches",
                        "match_words",
                        "rating_history",
                        "practice_words",
                        "user_words");

        // Where the chain leaves the table everything else edits: V3 traded the
        // Telegram identity for Google's, V4 added the deletion marker, V5 the
        // optimistic lock, V6 the counter a signed-out token is measured
        // against, V7 the clock Glicko-2's inactivity growth counts from.
        assertThat(columnsOf("fresh", "users"))
                .contains("google_subject", "deleted_at", "version", "token_generation", "rating_period_at")
                .doesNotContain("telegram_id");

        // Partial indexes are the reason this test needs PostgreSQL at all:
        // H2 accepts neither of these, so the H2 suite proves nothing about
        // them, and losing the predicate would turn one into a unique index
        // over every row.
        assertThat(indexDefinition("fresh", "ix_users_deleted_at")).contains("deleted_at IS NOT NULL");
        assertThat(indexDefinition("fresh", "ux_friend_requests_pending"))
                .contains("UNIQUE")
                .contains("'PENDING'");

        // Every restart re-runs migrate against a schema that is already up to
        // date; it has to be a no-op rather than an error.
        assertThat(migrate("fresh", null).migrationsExecuted).isZero();
    }

    /**
     * An upgrade of a live database. The rows go in at {@code V2} — the schema
     * of a server that shipped before Google sign-in — and the rest of the
     * chain runs over them.
     */
    @Test
    void anExistingDatabaseIsUpgradedWithItsRowsIntact() throws SQLException {
        assertThat(migrate("upgrade", "2").migrationsExecuted).isEqualTo(2);
        execute(
                "upgrade",
                """
                insert into users (telegram_id, nickname, display_name, rating) values
                    (1001, 'aziza_m', 'Aziza', 1420),
                    (1002, 'bekzod_99', 'Bekzod', 1180)
                """);
        // One of the two has a rated game behind her and the other has none,
        // which is the fork V7's backfill has to get right — see the assertions
        // on rating_period_at below.
        execute(
                "upgrade",
                """
                insert into rating_history (user_id, rating, recorded_at)
                select id, 1420, timestamptz '2026-01-02 03:04:05+00' from users where nickname = 'aziza_m'
                """);

        assertThat(migrate("upgrade", null).migrationsExecuted).isEqualTo(5);

        // The rows are the point: an upgrade that empties the users table would
        // have passed every assertion in the test above.
        assertThat(query("upgrade", "select nickname from users order by nickname"))
                .containsExactly("aziza_m", "bekzod_99");
        assertThat(columnsOf("upgrade", "users")).doesNotContain("telegram_id");

        // V3 creates the unique index on google_subject before it drops
        // telegram_id, so it meets two rows that both leave the new column
        // empty. It survives only because PostgreSQL counts nulls as distinct —
        // which is also what lets dev-login accounts, which have no Google
        // identity at all, coexist.
        assertThat(query("upgrade", "select google_subject from users")).containsOnlyNulls();

        // V5 adds a not-null column to a populated table. Without its default
        // the migration would fail outright; with it, the rows that were
        // already there have to read back as 0, because the entity maps this to
        // a primitive long and a null would break the first duel they settle.
        assertThat(query("upgrade", "select version from users")).containsExactly("0", "0");

        // V6 is the same shape and the same trap, and the value matters twice
        // over here: every token these two players are holding predates the
        // counter and carries none, so all of them are refused whatever this
        // says — but the accounts have to come back on generation zero, or the
        // token their very next sign-in produces would be stamped with a number
        // the column disagrees with and be dead on arrival.
        assertThat(query("upgrade", "select token_generation from users")).containsExactly("0", "0");

        // V7 is a not-null column with no default at all, so the backfill in the
        // middle of it is the whole migration. Defaulting it to now() would have
        // been the easy way and the wrong one: every existing player would be
        // recorded as having just played, and the idle time they had actually
        // served — the only thing the column exists to measure — would be
        // written off on the day it shipped.
        assertThat(query(
                        "upgrade",
                        "select to_char(rating_period_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS')"
                                + " from users where nickname = 'aziza_m'"))
                .as("a player with rated history is dated from her newest rating_history row")
                .containsExactly("2026-01-02 03:04:05");
        assertThat(query(
                        "upgrade",
                        "select count(*) from users"
                                + " where nickname = 'bekzod_99' and rating_period_at = created_at"))
                .as("a player who has never settled a rated duel falls back to when he signed up")
                .containsExactly("1");
    }

    // --------------------------------------------------------------- helpers

    /** Runs the production migrations into {@code schema}; {@code target} null means all of them. */
    private static MigrateResult migrate(String schema, String target) {
        FluentConfiguration flyway = Flyway.configure()
                .dataSource(
                        MigrationDatabase.jdbcUrl(),
                        MigrationDatabase.username(),
                        MigrationDatabase.password())
                // The real files, not a copy: a copy would drift.
                .locations("classpath:db/migration")
                .schemas(schema)
                // As application.yml configures it.
                .baselineOnMigrate(true);
        if (target != null) {
            flyway.target(target);
        }
        return flyway.load().migrate();
    }

    private static List<String> columnsOf(String schema, String table) throws SQLException {
        return query(
                schema,
                "select column_name from information_schema.columns"
                        + " where table_schema = current_schema() and table_name = '" + table + "'");
    }

    private static List<String> tables(String schema) throws SQLException {
        return query(
                schema,
                "select table_name from information_schema.tables"
                        + " where table_schema = current_schema() and table_type = 'BASE TABLE'");
    }

    /** The {@code create index} PostgreSQL rebuilt from what the migration actually left behind. */
    private static String indexDefinition(String schema, String index) throws SQLException {
        List<String> found =
                query(schema, "select indexdef from pg_indexes where schemaname = current_schema()"
                        + " and indexname = '" + index + "'");
        assertThat(found).as("index %s", index).hasSize(1);
        return found.get(0);
    }

    /** The first column of every row, in the order the query returned them. */
    private static List<String> query(String schema, String sql) throws SQLException {
        try (Connection connection = connect(schema);
                Statement statement = connection.createStatement();
                ResultSet rows = statement.executeQuery(sql)) {
            List<String> values = new ArrayList<>();
            while (rows.next()) {
                values.add(rows.getString(1));
            }
            return values;
        }
    }

    private static void execute(String schema, String sql) throws SQLException {
        try (Connection connection = connect(schema);
                Statement statement = connection.createStatement()) {
            statement.execute(sql);
        }
    }

    /**
     * A connection whose unqualified table names resolve inside {@code schema},
     * the way Flyway's own connection did while it was migrating it.
     */
    private static Connection connect(String schema) throws SQLException {
        Connection connection = DriverManager.getConnection(
                MigrationDatabase.jdbcUrl(),
                MigrationDatabase.username(),
                MigrationDatabase.password());
        try (Statement statement = connection.createStatement()) {
            statement.execute("set search_path to " + schema);
        }
        return connection;
    }
}
