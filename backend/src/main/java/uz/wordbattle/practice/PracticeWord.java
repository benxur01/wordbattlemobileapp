package uz.wordbattle.practice;

import jakarta.persistence.*;

@Entity
@Table(name = "practice_words")
public class PracticeWord {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "word", nullable = false, unique = true, length = 32)
    private String word;

    @Column(name = "ipa", length = 48)
    private String ipa;

    @Column(name = "meaning", nullable = false, length = 255)
    private String meaning;

    protected PracticeWord() {}

    public PracticeWord(String word, String ipa, String meaning) {
        this.word = word;
        this.ipa = ipa;
        this.meaning = meaning;
    }

    public Long getId() { return id; }
    public String getWord() { return word; }
    public String getIpa() { return ipa; }
    public String getMeaning() { return meaning; }
}
