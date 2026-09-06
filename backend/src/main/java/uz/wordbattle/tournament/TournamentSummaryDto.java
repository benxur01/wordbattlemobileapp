package uz.wordbattle.tournament;

/**
 * The lobby's "an active tournament exists" discovery card, and the browse
 * list's row — anyone signed in may read either. {@code acceptedCount}/{@code
 * size} is the "12/32" a stranger reads before deciding whether to join;
 * {@code minRating} is set only on a {@code GLOBAL} row.
 *
 * <p>{@code format} is {@code "solo"} or {@code "team"}, and {@code
 * acceptedCount}/{@code size} counts seats either way — a {@code "team"} row
 * reading "3/4" has three full teams, six people.
 */
public record TournamentSummaryDto(
        Long id,
        String name,
        int size,
        String status,
        String visibility,
        String kind,
        int acceptedCount,
        Double minRating,
        String format) {}
