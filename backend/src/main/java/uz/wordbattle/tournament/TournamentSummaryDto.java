package uz.wordbattle.tournament;

/** The lobby's "an active tournament exists" discovery card — anyone signed in may open it. */
public record TournamentSummaryDto(Long id, String name, int size, String status) {}
