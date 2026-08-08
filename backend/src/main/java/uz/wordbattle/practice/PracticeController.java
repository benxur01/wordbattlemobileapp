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
}
