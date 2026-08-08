package uz.wordbattle.practice;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.HashSet;
import java.util.Set;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.ClassPathResource;

/**
 * Loads the practice-screen vocabulary from a bundled TSV on every start,
 * inserting whatever is missing. Keeping the content in a resource rather than
 * a migration means the practice screen works on a fresh database, an H2 test
 * run, or after new words are added — without a schema change.
 */
@Configuration
public class PracticeWordSeeder {

    private static final Logger log = LoggerFactory.getLogger(PracticeWordSeeder.class);

    @Bean
    ApplicationRunner seedPracticeWords(PracticeWordRepository repository) {
        return args -> {
            Set<String> existing = new HashSet<>();
            repository.findAll().forEach(word -> existing.add(word.getWord()));

            int added = 0;
            try (var in = new ClassPathResource("words/practice-words.tsv").getInputStream();
                    var reader = new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    String[] parts = line.split("\t", 3);
                    if (parts.length < 3) continue;
                    if (existing.contains(parts[0])) continue;
                    repository.save(new PracticeWord(parts[0], parts[1], parts[2]));
                    added++;
                }
            }
            if (added > 0) log.info("Seeded {} practice words", added);
        };
    }
}
