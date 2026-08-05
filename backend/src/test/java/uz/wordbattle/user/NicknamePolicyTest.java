package uz.wordbattle.user;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Set;
import org.junit.jupiter.api.Test;
import uz.wordbattle.user.NicknamePolicy.Result;

class NicknamePolicyTest {

    @Test
    void acceptsTheDocumentedAlphabet() {
        assertThat(NicknamePolicy.validate("jasur_07")).isEqualTo(Result.OK);
        assertThat(NicknamePolicy.validate("sardor.eng")).isEqualTo(Result.OK);
        assertThat(NicknamePolicy.validate("MALIKA_X")).isEqualTo(Result.OK);
    }

    @Test
    void rejectsShortLongAndForeignCharacters() {
        assertThat(NicknamePolicy.validate("ab")).isEqualTo(Result.TOO_SHORT);
        assertThat(NicknamePolicy.validate("a".repeat(17))).isEqualTo(Result.TOO_LONG);
        assertThat(NicknamePolicy.validate("jasur 07")).isEqualTo(Result.BAD_CHARACTERS);
        assertThat(NicknamePolicy.validate("жасур")).isEqualTo(Result.BAD_CHARACTERS);
        assertThat(NicknamePolicy.validate("admin")).isEqualTo(Result.RESERVED);
    }

    @Test
    void suggestionsAreFreeValidAndDistinct() {
        Set<String> taken = Set.of("malika_x", "malika_x_uz", "the_malika_x");
        List<String> suggestions = NicknamePolicy.suggestions("malika_x", taken::contains);

        assertThat(suggestions).hasSize(3).doesNotHaveDuplicates();
        assertThat(suggestions).allSatisfy(s -> {
            assertThat(taken).doesNotContain(s);
            assertThat(NicknamePolicy.validate(s)).isEqualTo(Result.OK);
        });
    }

    @Test
    void suggestionsStayWithinTheLengthLimit() {
        List<String> suggestions = NicknamePolicy.suggestions("abcdefghijklmno", s -> false);
        assertThat(suggestions).allSatisfy(s -> assertThat(s.length()).isLessThanOrEqualTo(16));
    }
}
