package uz.wordbattle.practice;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;
import uz.wordbattle.common.ApiException;
import uz.wordbattle.config.AppProperties;
import uz.wordbattle.dictionary.DictionaryService;

/**
 * Curated rare-letter practice drills for letters that commonly decide fast
 * word-chain duels (currently {@code x} and {@code q}).
 */
@Service
public class RareLetterDrillService {

    public static final int DEFAULT_TARGET_COUNT = 5;

    private record PromptSample(String word, String ipa, String meaning) {}

    private record DrillTemplate(
            char letter,
            String badge,
            String title,
            String subtitle,
            String tip,
            List<PromptSample> samples) {}

    public record RareLetterDrillDto(
            String letter,
            String badge,
            String title,
            String subtitle,
            String tip,
            String promptWord,
            String promptIpa,
            String promptMeaning,
            int targetCount,
            List<String> hints) {}

    private static final List<Character> SUPPORTED_ORDER = List.of('x', 'q');

    private static final Map<Character, DrillTemplate> TEMPLATES = Map.of(
            'x',
            new DrillTemplate(
                    'x',
                    "NOYOB · X",
                    "X harfi hujumi",
                    "Raqib X bilan tugagan so'z tashlaganda tez javob bering",
                    "Ingliz tilida X bilan boshlanadigan so'zlar kam: xenon, xylem, xerox, xray, xylophone ni yodda tuting.",
                    List.of(
                            new PromptSample("apex", "/ˈeɪpeks/", "cho'qqi — eng yuqori nuqta"),
                            new PromptSample("matrix", "/ˈmeɪtrɪks/", "matritsa — qator va ustunlar jadvali"),
                            new PromptSample("vortex", "/ˈvɔːteks/", "girdob — kuchli aylanma oqim"),
                            new PromptSample("helix", "/ˈhiːlɪks/", "spiral — burama chiziq yoki tuzilma"),
                            new PromptSample("phoenix", "/ˈfiːnɪks/", "feniks — qayta tiriluvchi afsonaviy qush"),
                            new PromptSample("syntax", "/ˈsɪntæks/", "sintaksis — til va kod tuzilish qoidasi"))),
            'q',
            new DrillTemplate(
                    'q',
                    "NOYOB · Q",
                    "Q harfi strategiyasi",
                    "«Qu-» birikmali tezkor so'z zanjirini mustahkamlang",
                    "Q dan keyin deyarli doim U keladi: quest, quartz, quench, quiver, quorum — kuchli javoblar.",
                    List.of(
                            new PromptSample("quartz", "/kwɔːts/", "kvars — shaffof va qattiq mineral tosh"),
                            new PromptSample("quantum", "/ˈkwɒntəm/", "kvant — energiyaning eng kichik bo'lagi"),
                            new PromptSample("quench", "/kwentʃ/", "chanqoqni qondirmoq; olovni o'chirmoq"),
                            new PromptSample("quest", "/kwest/", "izlanish, maqsadli safar"),
                            new PromptSample("quiver", "/ˈkwɪvə/", "o'qdon; yengil titroq"),
                            new PromptSample("quorum", "/ˈkwɔːrəm/", "kvorum — qaror qabul qilish uchun yetarli son"))));

    private final DictionaryService dictionary;
    private final AppProperties props;

    public RareLetterDrillService(DictionaryService dictionary, AppProperties props) {
        this.dictionary = dictionary;
        this.props = props;
    }

    /** Returns all supported rare-letter drills ordered as X then Q. */
    public List<RareLetterDrillDto> listDrills(int offset) {
        return SUPPORTED_ORDER.stream().map(letter -> buildDrill(letter, offset)).toList();
    }

    /** Returns the drill payload for a specific rare letter (`x` or `q`). */
    public RareLetterDrillDto getDrill(String rawLetter, int offset) {
        if (rawLetter == null || rawLetter.isBlank()) {
            throw ApiException.badRequest("drill_letter_required", "Harf ko'rsatilmagan");
        }
        char normalized = Character.toLowerCase(rawLetter.trim().charAt(0));
        if (!TEMPLATES.containsKey(normalized) || rawLetter.trim().length() != 1) {
            throw ApiException.badRequest(
                    "drill_letter_unsupported", "Faqat X va Q harflari uchun maxsus mashq mavjud");
        }
        return buildDrill(normalized, offset);
    }

    private RareLetterDrillDto buildDrill(char letter, int offset) {
        DrillTemplate template = TEMPLATES.get(letter);
        long day = LocalDate.now(props.timeZone()).toEpochDay();
        int idx = Math.floorMod(day + Math.max(0, offset), template.samples().size());
        PromptSample sample = template.samples().get(idx);

        // Pass explicit minLength=3 so rare dictionary words also fill scarce X hints cleanly.
        List<String> hints = dictionary.hints(letter, List.of(), 6, 3, null);
        return new RareLetterDrillDto(
                String.valueOf(letter),
                template.badge(),
                template.title(),
                template.subtitle(),
                template.tip(),
                sample.word(),
                sample.ipa(),
                sample.meaning(),
                DEFAULT_TARGET_COUNT,
                hints);
    }
}
