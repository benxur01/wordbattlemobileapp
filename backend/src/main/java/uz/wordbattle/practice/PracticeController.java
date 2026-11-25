package uz.wordbattle.practice;

import java.time.LocalDate;
import java.util.List;
import org.springframework.web.bind.annotation.*;
import uz.wordbattle.common.ApiException;
import uz.wordbattle.config.AppProperties;
import uz.wordbattle.dictionary.DictionaryService;

@RestController
@RequestMapping("/api/practice")
public class PracticeController {

    private final PracticeWordRepository words;
    private final DictionaryService dictionary;
    private final AppProperties props;

    public PracticeController(PracticeWordRepository words, DictionaryService dictionary, AppProperties props) {
        this.words = words;
        this.dictionary = dictionary;
        this.props = props;
    }

    public record WordOfTheDay(String word, String ipa, String meaning) {}

    public record WordCheckResult(String word, boolean valid, String reason) {}

    /** Rotates once per day so the practice screen has fresh content. */
    @GetMapping("/word")
    public WordOfTheDay wordOfTheDay() {
        List<PracticeWord> all = words.findAllByOrderByIdAsc();
        if (all.isEmpty()) {
            throw ApiException.notFound("no_practice_words", "Mashq so'zlari yuklanmagan");
        }
        long day = LocalDate.now(props.timeZone()).toEpochDay();
        PracticeWord word = all.get((int) Math.floorMod(day, all.size()));
        return new WordOfTheDay(word.getWord(), word.getIpa(), word.getMeaning());
    }

    /** The "?" button: a few common words starting with the required letter. */
    @GetMapping("/hints")
    public List<String> hints(
            @RequestParam("letter") String letter,
            @RequestParam(value = "limit", defaultValue = "3") int limit) {
        if (letter == null || letter.isBlank()) {
            throw ApiException.badRequest("letter_required", "Harf ko'rsatilmagan");
        }
        char first = letter.trim().toLowerCase().charAt(0);
        if (first < 'a' || first > 'z') {
            throw ApiException.badRequest("letter_invalid", "Faqat ingliz harfi");
        }
        // Clamped rather than trusted: `limit=-1` reached `new ArrayList<>(-1)`
        // and came back as a 500.
        return dictionary.hints(first, List.of(), Math.max(1, Math.min(limit, 10)));
    }

    /** Interactive practice validation: checks chain rules and the duel dictionary. */
    @GetMapping("/check")
    public WordCheckResult check(
            @RequestParam("word") String rawWord,
            @RequestParam(value = "requiredLetter", required = false) String requiredLetter) {
        String word = rawWord == null ? "" : rawWord.trim().toLowerCase();
        if (word.isEmpty()) {
            return new WordCheckResult("", false, "Avval so'z yozing");
        }
        if (word.length() > props.limits().maxWordLength()) {
            return new WordCheckResult(word, false, "Bunday uzun so'z yo'q");
        }
        if (!word.chars().allMatch(c -> c >= 'a' && c <= 'z')) {
            return new WordCheckResult(word, false, "Faqat ingliz harflari");
        }
        int minLength = props.duel().minWordLength();
        if (word.length() < minLength) {
            return new WordCheckResult(word, false, "Kamida " + minLength + " ta harf");
        }
        if (requiredLetter != null && !requiredLetter.isBlank()) {
            char expected = Character.toLowerCase(requiredLetter.trim().charAt(0));
            if (word.charAt(0) != expected) {
                return new WordCheckResult(
                        word,
                        false,
                        "«" + Character.toUpperCase(expected) + "» harfi bilan boshlanishi kerak");
            }
        }
        if (!dictionary.isValid(word)) {
            return new WordCheckResult(word, false, "Bu so'z ingliz lug'atida yo'q");
        }
        return new WordCheckResult(word, true, null);
    }
}
