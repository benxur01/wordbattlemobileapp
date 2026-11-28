package uz.wordbattle.practice;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
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

class RareLetterDrillServiceTest {

    private DictionaryService dictionary;
    private RareLetterDrillService service;

    @BeforeEach
    void setUp() {
        dictionary = mock(DictionaryService.class);
        AppProperties props = new Binder(ConfigurationPropertySources.from(
                        new MapPropertySource("test", Map.of("wordbattle.time-zone", "Asia/Tashkent"))))
                .bind("wordbattle", Bindable.of(AppProperties.class))
                .get();
        service = new RareLetterDrillService(dictionary, props);
    }

    @Test
    void listsBothXAndQDrillsInDeterministicOrder() {
        when(dictionary.hints(eq('x'), anyList(), eq(6), eq(3), eq((Integer) null)))
                .thenReturn(List.of("xray", "xenon", "xylem"));
        when(dictionary.hints(eq('q'), anyList(), eq(6), eq(3), eq((Integer) null)))
                .thenReturn(List.of("queen", "quartz", "quest"));

        var list = service.listDrills(0);

        assertThat(list).hasSize(2);
        assertThat(list.get(0).letter()).isEqualTo("x");
        assertThat(list.get(0).badge()).isEqualTo("NOYOB · X");
        assertThat(list.get(0).hints()).containsExactly("xray", "xenon", "xylem");
        assertThat(list.get(0).targetCount()).isEqualTo(RareLetterDrillService.DEFAULT_TARGET_COUNT);
        assertThat(list.get(1).letter()).isEqualTo("q");
        assertThat(list.get(1).badge()).isEqualTo("NOYOB · Q");
        assertThat(list.get(1).hints()).containsExactly("queen", "quartz", "quest");
    }

    @Test
    void rotatesPromptSampleWhenOffsetIncreases() {
        when(dictionary.hints(eq('x'), anyList(), eq(6), eq(3), eq((Integer) null)))
                .thenReturn(List.of("xray"));

        var first = service.getDrill("X", 0);
        var next = service.getDrill(" x ", 1);

        assertThat(first.letter()).isEqualTo("x");
        assertThat(first.promptWord()).endsWith("x");
        assertThat(next.promptWord()).endsWith("x");
        assertThat(next.promptWord()).isNotEqualTo(first.promptWord());
    }

    @Test
    void rejectsUnsupportedOrMalformedLetters() {
        assertThatThrownBy(() -> service.getDrill("  ", 0)).isInstanceOf(ApiException.class);
        assertThatThrownBy(() -> service.getDrill("z", 0)).isInstanceOf(ApiException.class);
        assertThatThrownBy(() -> service.getDrill("xq", 0)).isInstanceOf(ApiException.class);
    }
}
