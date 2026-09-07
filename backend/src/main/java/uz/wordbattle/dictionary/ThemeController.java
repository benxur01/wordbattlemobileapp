package uz.wordbattle.dictionary;

import java.util.Arrays;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * The themes the bot picker offers. Reference data that changes only when the
 * server is rebuilt, so it goes over REST like the practice word rather than
 * down the socket — the app asks once, when the picker is opened, and the
 * duel itself is still started by {@code queue.bot}.
 */
@RestController
@RequestMapping("/api/themes")
public class ThemeController {

    public record ThemeDto(String id, String name) {}

    @GetMapping
    public List<ThemeDto> themes() {
        return Arrays.stream(WordTheme.values())
                .map(theme -> new ThemeDto(theme.id(), theme.label()))
                .toList();
    }
}
