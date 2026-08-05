package uz.wordbattle.practice;

import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.List;
import org.springframework.web.bind.annotation.*;
import uz.wordbattle.common.ApiException;
import uz.wordbattle.dictionary.DictionaryService;

@RestController
@RequestMapping("/api/practice")
public class PracticeController {

    private final PracticeWordRepository words;
    private final DictionaryService dictionary;

    public PracticeController(PracticeWordRepository words, DictionaryService dictionary) {
        this.words = words;
        this.dictionary = dictionary;
    }

    public record WordOfTheDay(String word, String ipa, String meaning) {}

    /** Rotates once per day so the practice screen has fresh content. */
    @GetMapping("/word")
    public WordOfTheDay wordOfTheDay() {
        List<PracticeWord> all = words.findAllByOrderByIdAsc();
        if (all.isEmpty()) {
            throw ApiException.notFound("no_practice_words", "Mashq so'zlari yuklanmagan");
        }
        long day = LocalDate.now(ZoneOffset.UTC).toEpochDay();
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
        return dictionary.hints(letter.trim().toLowerCase().charAt(0), List.of(), Math.min(limit, 10));
    }
}
