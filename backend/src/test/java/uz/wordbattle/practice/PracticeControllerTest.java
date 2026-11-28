package uz.wordbattle.practice;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.boot.context.properties.bind.Bindable;
import org.springframework.boot.context.properties.bind.Binder;
import org.springframework.boot.context.properties.source.ConfigurationPropertySources;
import org.springframework.core.env.MapPropertySource;
import uz.wordbattle.common.ApiException;
import uz.wordbattle.config.AppProperties;
import uz.wordbattle.dictionary.DictionaryService;

class PracticeControllerTest {

    private PracticeWordRepository words;
    private DictionaryService dictionary;
    private PracticeController controller;

    @BeforeEach
    void setUp() {
        words = mock(PracticeWordRepository.class);
        dictionary = mock(DictionaryService.class);
        AppProperties props = new Binder(ConfigurationPropertySources.from(
                        new MapPropertySource("test", Map.of("wordbattle.time-zone", "Asia/Tashkent"))))
                .bind("wordbattle", Bindable.of(AppProperties.class))
                .get();
        controller = new PracticeController(words, dictionary, props);
    }

    @Test
    void checkRejectsBlankAndNonEnglishCharacters() {
        var empty = controller.check("   ", "r");
        assertThat(empty.valid()).isFalse();
        assertThat(empty.reason()).isEqualTo("Avval so'z yozing");

        var symbols = controller.check("riv3r!", "r");
        assertThat(symbols.valid()).isFalse();
        assertThat(symbols.reason()).isEqualTo("Faqat ingliz harflari");
    }

    @Test
    void checkEnforcesMinLengthAndRequiredLetter() {
        var shortWord = controller.check("ri", "r");
        assertThat(shortWord.valid()).isFalse();
        assertThat(shortWord.reason()).isEqualTo("Kamida 3 ta harf");

        var wrongLetter = controller.check("apple", "R");
        assertThat(wrongLetter.valid()).isFalse();
        assertThat(wrongLetter.reason()).isEqualTo("«R» harfi bilan boshlanishi kerak");
    }

    @Test
    void checkVerifiesAgainstDictionaryService() {
        when(dictionary.isValid("river")).thenReturn(true);
        when(dictionary.isValid("rzzzz")).thenReturn(false);

        var accepted = controller.check("  RIVER ", "r");
        assertThat(accepted.valid()).isTrue();
        assertThat(accepted.word()).isEqualTo("river");
        assertThat(accepted.reason()).isNull();

        var rejected = controller.check("rzzzz", "r");
        assertThat(rejected.valid()).isFalse();
        assertThat(rejected.reason()).isEqualTo("Bu so'z ingliz lug'atida yo'q");

        var optionalLetterAccepted = controller.check("river", "  ");
        assertThat(optionalLetterAccepted.valid()).isTrue();
    }

    @Test
    void hintsClampsLimitAndValidatesLetter() {
        when(dictionary.hints(eq('r'), anyList(), anyInt())).thenReturn(List.of("river", "rocket"));

        assertThat(controller.hints("R", 50)).containsExactly("river", "rocket");
        assertThatThrownBy(() -> controller.hints("1", 3)).isInstanceOf(ApiException.class);
        assertThatThrownBy(() -> controller.hints("  ", 3)).isInstanceOf(ApiException.class);
    }

    @Test
    void hintsForwardsLengthFiltersAndRejectsInvalidBounds() {
        when(dictionary.hints(eq('r'), anyList(), eq(6), eq(3), eq(4))).thenReturn(List.of("rain", "rock"));
        when(dictionary.hints(eq('r'), anyList(), eq(6), eq(7), eq((Integer) null))).thenReturn(List.of("rainbow"));

        assertThat(controller.hints("r", 6, 3, 4)).containsExactly("rain", "rock");
        assertThat(controller.hints("r", 6, 7, null)).containsExactly("rainbow");

        assertThatThrownBy(() -> controller.hints("r", 6, 0, 4)).isInstanceOf(ApiException.class);
        assertThatThrownBy(() -> controller.hints("r", 6, 6, 3)).isInstanceOf(ApiException.class);
    }

    @Test
    void exposesRareLetterDrillsForXAndQ() {
        when(dictionary.hints(eq('x'), anyList(), eq(6), eq(3), eq((Integer) null)))
                .thenReturn(List.of("xray", "xenon"));
        when(dictionary.hints(eq('q'), anyList(), eq(6), eq(3), eq((Integer) null)))
                .thenReturn(List.of("queen", "quartz"));

        var drills = controller.drills(0);
        assertThat(drills).extracting(RareLetterDrillService.RareLetterDrillDto::letter).containsExactly("x", "q");

        var qDrill = controller.drill("Q", 1);
        assertThat(qDrill.letter()).isEqualTo("q");
        assertThat(qDrill.hints()).containsExactly("queen", "quartz");
        assertThatThrownBy(() -> controller.drill("z", 0)).isInstanceOf(ApiException.class);
    }
}
