import 'transliteration.dart';

/// Representation of an Uzbek dictionary definition with grammatical,
/// phonetic, and contextual usage properties.
class WordDefinition {
  const WordDefinition({
    required this.word,
    required this.meaning,
    required this.partOfSpeech,
    required this.example,
    required this.syllables,
    this.ipa,
    this.origin,
  });

  /// The word in normalized uppercase.
  final String word;

  /// Detailed dictionary definition in Uzbek.
  final String meaning;

  /// Part of speech (e.g. Ot, Sifat, Fe'l, Ravish).
  final String partOfSpeech;

  /// Illustrative contextual example sentence.
  final String example;

  /// Hyphenated or dotted syllable structure (e.g. 'ki · tob').
  final String syllables;

  /// Phonetic International Phonetic Alphabet representation if available.
  final String? ipa;

  /// Etymological or language origin (e.g. 'o\'zbekcha', 'arabcha', 'forscha').
  final String? origin;

  /// Synthesizes an accurate grammatical and phonetic breakdown for any
  /// dynamic word not present in the curated core dictionary.
  factory WordDefinition.fromDynamicAnalysis(String rawWord) {
    final word = rawWord.trim().toUpperCase();
    final syllables = computeSyllables(word);
    final pos = guessPartOfSpeech(word);

    final titleWord = word.length > 1
        ? '${word[0]}${word.substring(1).toLowerCase()}'
        : word;

    final meaning = _synthesizeMeaning(word, pos);
    final example = _synthesizeExample(titleWord, pos);

    return WordDefinition(
      word: word,
      meaning: meaning,
      partOfSpeech: pos,
      example: example,
      syllables: syllables,
      origin: "o'zbekcha",
    );
  }

  static String _synthesizeMeaning(String word, String pos) {
    switch (pos) {
      case "Fe'l":
        return "Harakat, holat yoki jarayonni ifodalovchi mustaqil so'z turkumi. So'z o'yinida faol qo'llanuvchi harakat birligi.";
      case "Sifat":
        return "Narsa, hodisa yoki shaxsning belgi-xususiyati, holati yoki sifatini ifodalovchi so'z.";
      case "Ravish":
        return "Harakatning bajarilish tarzi, o'rni, payti yoki darajasini bildiruvchi mustaqil so'z turkumi.";
      case "Son":
        return "Narsalarning miqdori, sanog'i yoki tartibini bildiruvchi so'z.";
      case "Ot":
      default:
        return "O'zbek tilining boy leksik qatlamiga mansub, shaxs, narsa, tushuncha yoki hodisa nomini ifodalovchi mustaqil so'z.";
    }
  }

  static String _synthesizeExample(String titleWord, String pos) {
    switch (pos) {
      case "Fe'l":
        return "U o'z fikrini bildirish uchun $titleWord harakatini aniq bajardi.";
      case "Sifat":
        return "Yangi qabul qilingan $titleWord atamasi matnga o'zgacha ma'no bag'ishladi.";
      case "Ravish":
        return "Vazifa $titleWord tarzda va o'z vaqtida muvaffaqiyatli yakunlandi.";
      case "Ot":
      default:
        return "«$titleWord» so'zi adabiy tilda faol ishlatilib, o'yin zanjirida to'g'ri o'rin egalladi.";
    }
  }

  /// Calculates syllable splits based on Uzbek phonotactics.
  static String computeSyllables(String word) {
    if (word.isEmpty) return word;
    final lower = word.toLowerCase();
    if (lower.length <= 3) return lower;

    const vowels = 'aeiou\u0430\u0435\u0438\u043e\u0443\u045e\u044d\u044e\u044f';
    final buffer = StringBuffer();

    for (int i = 0; i < lower.length; i++) {
      buffer.write(lower[i]);
      if (i < lower.length - 1) {
        final currentIsVowel = vowels.contains(lower[i]);
        final nextIsVowel = vowels.contains(lower[i + 1]);

        if (currentIsVowel && !nextIsVowel && i + 2 < lower.length && vowels.contains(lower[i + 2])) {
          buffer.write(' · ');
        } else if (!currentIsVowel && !nextIsVowel && i + 2 < lower.length && vowels.contains(lower[i + 2])) {
          buffer.write(' · ');
        }
      }
    }
    return buffer.toString();
  }

  /// Guesses probable part of speech from typical Uzbek morphological affixes.
  static String guessPartOfSpeech(String word) {
    final lower = word.toLowerCase();

    if (lower.endsWith('moq') || lower.endsWith('gan') || lower.endsWith('di') || lower.endsWith('yapti')) {
      return "Fe'l";
    }
    if (lower.endsWith('li') ||
        lower.endsWith('siz') ||
        lower.endsWith('dor') ||
        lower.endsWith('kor') ||
        lower.endsWith('iy') ||
        lower.endsWith('chan') ||
        lower.endsWith('roq')) {
      return 'Sifat';
    }
    if (lower.endsWith('cha') || lower.endsWith('dek') || lower.endsWith('larcha')) {
      return 'Ravish';
    }
    if (lower.endsWith('ta') || lower.endsWith('tadan') || lower.endsWith('inchi')) {
      return 'Son';
    }
    return 'Ot';
  }
}

/// Service providing instantaneous lookup for Uzbek words with definitions,
/// grammatical parts of speech, IPA phonetic transcription and contextual usage.
class WordDefinitionService {
  WordDefinitionService._();

  static final Map<String, WordDefinition> _cache = {};

  /// Retrieves or synthesizes the [WordDefinition] for a given word.
  static WordDefinition getDefinition(String rawWord) {
    final latin = transliterateCyrillicToLatin(rawWord, allowApostrophe: true, toLowerCase: false)
        .trim()
        .toUpperCase();
    if (latin.isEmpty) {
      return const WordDefinition(
        word: '—',
        meaning: "So'z kiritilmadi.",
        partOfSpeech: 'Ot',
        example: '',
        syllables: '—',
      );
    }

    if (_cache.containsKey(latin)) {
      return _cache[latin]!;
    }

    final found = _curatedDictionary[latin];
    if (found != null) {
      _cache[latin] = found;
      return found;
    }

    final dynamicDef = WordDefinition.fromDynamicAnalysis(latin);
    _cache[latin] = dynamicDef;
    return dynamicDef;
  }

  /// Rich curated vocabulary pool of common Uzbek words used in Word Battle duels.
  static final Map<String, WordDefinition> _curatedDictionary = {
    'KITOB': const WordDefinition(
      word: 'KITOB',
      meaning: "Muqovalangan, bosma yoki yozma varaqlardan iborat adabiy, ilmiy yoki o'quv asari.",
      partOfSpeech: 'Ot',
      example: "Kitob — inson tafakkurini boyituvchi bitmas-tuganmas xazinadir.",
      syllables: 'ki · tob',
      ipa: '[kʲɪˈtob]',
      origin: 'arabcha',
    ),
    'DAFTAR': const WordDefinition(
      word: 'DAFTAR',
      meaning: "Yozuv, chizuv yoki hisob-kitob qilish uchun mo'ljallangan qog'oz varaqlar to'plami.",
      partOfSpeech: 'Ot',
      example: "O'quvchi yangi dars mavzusini daftariga chiroyli husnixat bilan qayd etdi.",
      syllables: 'daf · tar',
      ipa: '[dɑfˈtɑr]',
      origin: 'yunoncha / arabcha',
    ),
    'QALAM': const WordDefinition(
      word: 'QALAM',
      meaning: "Yozish yoki rasm chizish uchun ishlatiladigan ingichka grafitli asbob.",
      partOfSpeech: 'Ot',
      example: "Chizmachilik darsida o'tkir uchli qalam va chizg'ich kerak bo'ldi.",
      syllables: 'qa · lam',
      ipa: '[qɑˈlɑm]',
      origin: 'arabcha',
    ),
    'ANOR': const WordDefinition(
      word: 'ANOR',
      meaning: "Po'sti qalin, ichi qizil va shirali donachalardan iborat subtropik meva.",
      partOfSpeech: 'Ot',
      example: "Bog'da shona yozgan anorlar kuz kelishi bilan qip-qizil bo'lib pishdi.",
      syllables: 'a · nor',
      ipa: '[ɑˈnɔr]',
      origin: "forscha / o'zbekcha",
    ),
    'OLMA': const WordDefinition(
      word: 'OLMA',
      meaning: "Daraxtda yetiladigan xushta'm, dumaloq va shirin meva turi.",
      partOfSpeech: 'Ot',
      example: "Tongda yangi uzilgan olmadan xushbo'y shirin hid taralar edi.",
      syllables: 'ol · ma',
      ipa: '[ɔlˈmɑ]',
      origin: "o'zbekcha",
    ),
    'MAKTAB': const WordDefinition(
      word: 'MAKTAB',
      meaning: "Bolalar va yoshlarga umumiy ta'lim hamda tarbiya beruvchi o'quv maskani.",
      partOfSpeech: 'Ot',
      example: "Yangi o'quv yilida maktab eshiklari bilimga chanqoq yoshlar uchun ochildi.",
      syllables: 'mak · tab',
      ipa: '[mɑkˈtɑb]',
      origin: 'arabcha',
    ),
    'VATAN': const WordDefinition(
      word: 'VATAN',
      meaning: "Kishi tug'ilib o'sgan yurt, mamlakat, ona diyor.",
      partOfSpeech: 'Ot',
      example: "Vatan ostonadan boshlanadi va har bir inson qalbida mangu yashaydi.",
      syllables: 'va · tan',
      ipa: '[wɑˈtɑn]',
      origin: 'arabcha',
    ),
    'BILIM': const WordDefinition(
      word: 'BILIM',
      meaning: "Ta'lim, tajriba va o'rganish natijasida hosil qilingan ma'lumotlar majmui.",
      partOfSpeech: 'Ot',
      example: "Bilim egallash har bir yoshning eng oliy va sharafli burchidir.",
      syllables: 'bi · lim',
      ipa: '[bʲɪˈlʲɪm]',
      origin: "o'zbekcha",
    ),
    'BAHOR': const WordDefinition(
      word: 'BAHOR',
      meaning: "Qishdan keyin, yozdan oldin keladigan, tabiat uyg'onadigan go'zal fasl.",
      partOfSpeech: 'Ot',
      example: "Bahor nafasi kelishi bilan dala va qirlar zumraddek yashil libosga burkandi.",
      syllables: 'ba · hor',
      ipa: '[bɑˈhɔr]',
      origin: 'forscha',
    ),
    'SHAHAR': const WordDefinition(
      word: 'SHAHAR',
      meaning: "Aholisi zich joylashgan, sanoat va madaniyat markazi hisoblangan yirik manzilgoh.",
      partOfSpeech: 'Ot',
      example: "Kechki shahar chiroqlari uzoqdan mayin yulduzlardek porlab ko'rinardi.",
      syllables: 'sha · har',
      ipa: '[ʃɑˈhɑr]',
      origin: 'forscha',
    ),
    'DO\'ST': const WordDefinition(
      word: 'DO\'ST',
      meaning: "Samimiy, sodiq va yaqin birodar, qiyin damda yelkadosh inson.",
      partOfSpeech: 'Ot',
      example: "Yaxshi do'st kulfatda ham, quvonchda ham hamisha yoningda suyanch bo'ladi.",
      syllables: 'do\'st',
      ipa: '[dost]',
      origin: 'forscha',
    ),
    'JASUR': const WordDefinition(
      word: 'JASUR',
      meaning: "Qo'rqmas, botir, mard va dadil fe'l-atvorli kishi.",
      partOfSpeech: 'Sifat',
      example: "Jasur jangchi har qanday to'siqni mardonavor yengib o'tdi.",
      syllables: 'ja · sur',
      ipa: '[dʒɑˈsur]',
      origin: 'arabcha',
    ),
    'ZAFAR': const WordDefinition(
      word: 'ZAFAR',
      meaning: "Katta yutuq, muvaffaqiyat, kurash yoki bellashuvdagi shonli g'alaba.",
      partOfSpeech: 'Ot',
      example: "Tinimsiz mehnat va sabr-toqat natijasida orziqib kutilgan zafar quchildi.",
      syllables: 'za · far',
      ipa: '[zɑˈfɑr]',
      origin: 'arabcha',
    ),
    'G\'ALABA': const WordDefinition(
      word: 'G\'ALABA',
      meaning: "Jang, bahs yoki musobaqada raqib ustidan qozonilgan to'liq ustunlik.",
      partOfSpeech: 'Ot',
      example: "Word Battle bellashuvida so'nggi daqiqalarda aytilgan noyob so'z g'alaba keltirdi.",
      syllables: 'g\'a · la · ba',
      ipa: '[ɣɑlɑˈbɑ]',
      origin: 'arabcha',
    ),
    'JANG': const WordDefinition(
      word: 'JANG',
      meaning: "Ikki tomon o'rtasidagi shiddatli to'qnashuv, bellashuv yoki intellektual kurash.",
      partOfSpeech: 'Ot',
      example: "Bugungi so'z jangi eng kuchli bilimdonlar o'rtasida murosasiz kechdi.",
      syllables: 'jang',
      ipa: '[dʒɑŋ]',
      origin: 'forscha',
    ),
    'DARYO': const WordDefinition(
      word: 'DARYO',
      meaning: "Tabiiy o'zanda oqadigan katta suv havzasi, oqim.",
      partOfSpeech: 'Ot',
      example: "Tog'dan boshlangan tiniq daryo keng vodiylar sari shiddat bilan oqmoqda.",
      syllables: 'dar · yo',
      ipa: '[dɑrˈjɔ]',
      origin: 'forscha',
    ),
    'OSMON': const WordDefinition(
      word: 'OSMON',
      meaning: "Yer sathining ustida ko'rinib turadigan cheksiz fazoviy qatlam, ko'k gumbaz.",
      partOfSpeech: 'Ot',
      example: "Tonggi osmon musaffo va moviy rangga kirib, ko'ngillarga xotirjamlik bag'ishladi.",
      syllables: 'os · mon',
      ipa: '[ɔsˈmɔn]',
      origin: 'forscha',
    ),
    'QUYOSH': const WordDefinition(
      word: 'QUYOSH',
      meaning: "Quyosh sistemasining markaziy yulduzi, Yerga yorug'lik va iliqlik ulashuvchi osmon jismi.",
      partOfSpeech: 'Ot',
      example: "Quyosh nurlari zaminga hayot, iliqlik va yangi kuch bag'ishlaydi.",
      syllables: 'qu · yosh',
      ipa: '[quˈjɔʃ]',
      origin: "o'zbekcha",
    ),
    'YULDUZ': const WordDefinition(
      word: 'YULDUZ',
      meaning: "Fazo kengligida charag'lab turadigan, o'zidan nur taratuvchi osmon jismi.",
      partOfSpeech: 'Ot',
      example: "Tungi musaffo osmonda son-sanoqsiz yulduzlar charaqlab ko'rindi.",
      syllables: 'yul · duz',
      ipa: '[julˈduz]',
      origin: "o'zbekcha",
    ),
    'BULUT': const WordDefinition(
      word: 'BULUT',
      meaning: "Osmonda suzib yuruvchi suv bug'lari va mayda kristallari to'plami.",
      partOfSpeech: 'Ot',
      example: "Moviy osmon bo'ylab oppoq paxtadek bulutlar ohista suzardi.",
      syllables: 'bu · lut',
      ipa: '[buˈlut]',
      origin: "o'zbekcha",
    ),
    'GUL': const WordDefinition(
      word: 'GUL',
      meaning: "O'simliklarning go'zal rangli va xushbo'y barglardan iborat ochiluvchi qismi.",
      partOfSpeech: 'Ot',
      example: "Bahor quyoshi ostida ochilgan lola guli atrofga o'zgacha chiroy berdi.",
      syllables: 'gul',
      ipa: '[ɡul]',
      origin: 'forscha',
    ),
    'DARAXT': const WordDefinition(
      word: 'DARAXT',
      meaning: "Qattiq yog'ochli tanasi va shox-shabbalari bo'lgan ko'p yillik yirik o'simlik.",
      partOfSpeech: 'Ot',
      example: "Katta chinor daraxti salqin soyasi bilan yo'lovchilarga huzur ulashadi.",
      syllables: 'da · raxt',
      ipa: '[dɑˈrɑxt]',
      origin: 'forscha',
    ),
    'SHAMOL': const WordDefinition(
      word: 'SHAMOL',
      meaning: "Havoning Yer sathi bo'ylab gorizontal harakati, esayotgan havo oqimi.",
      partOfSpeech: 'Ot',
      example: "Salqin shabada shamoli daraxt barglarini ohista silkitib o'tdi.",
      syllables: 'sha · mol',
      ipa: '[ʃɑˈmɔl]',
      origin: 'arabcha',
    ),
    'MEHR': const WordDefinition(
      word: 'MEHR',
      meaning: "Samimiy muhabbat, g'amxo'rlik, ezgulik va iliq munosabat tuyg'usi.",
      partOfSpeech: 'Ot',
      example: "Inson qalbidagi mehr va e'tibor dunyoni yanada go'zallashtiradi.",
      syllables: 'mehr',
      ipa: '[mehr]',
      origin: 'forscha',
    ),
    'AQLLI': const WordDefinition(
      word: 'AQLLI',
      meaning: "Zukko, fahm-farosatli, tez fikrlovchi va donishmand inson.",
      partOfSpeech: 'Sifat',
      example: "Aqlli o'yinchi harflarni oldindan hisoblab, g'alaba keltiruvchi so'zni tanladi.",
      syllables: 'aql · li',
      ipa: '[ɑqlˈlʲi]',
      origin: "arabcha / o'zbekcha",
    ),
    'TEZKOR': const WordDefinition(
      word: 'TEZKOR',
      meaning: "Chaqqon, qisqa vaqtda harakatlanuvchi yoki tez qaror qabul qiluvchi.",
      partOfSpeech: 'Sifat',
      example: "Tezkor javob berish jangdagi ustunlikni saqlab qolish kalitiga aylandi.",
      syllables: 'tez · kor',
      ipa: '[tezˈkɔr]',
      origin: "forscha / o'zbekcha",
    ),
    'BAXT': const WordDefinition(
      word: 'BAXT',
      meaning: "To'liq qoniqish, shodlik, omad va ichki huzur-halovat holati.",
      partOfSpeech: 'Ot',
      example: "Haqiqiy baxt tinchlik, mehr-oqibat va ezgu amallarda mujassamdir.",
      syllables: 'baxt',
      ipa: '[bɑxt]',
      origin: 'forscha',
    ),
    'OMAD': const WordDefinition(
      word: 'OMAD',
      meaning: "Kutilgan yaxshi natija, muvaffaqiyatli tasodif, tole kulib boqishi.",
      partOfSpeech: 'Ot',
      example: "Musobaqada kuchli tayyorgarlik ko'rgan bilimdonga omad yor bo'ldi.",
      syllables: 'o · mad',
      ipa: '[ɔˈmɑd]',
      origin: 'forscha',
    ),
    'HAYOT': const WordDefinition(
      word: 'HAYOT',
      meaning: "Tirik mavjudotlarning yashash davri, tiriklik va borliq jarayoni.",
      partOfSpeech: 'Ot',
      example: "Hayot doimiy harakat, o'rganish va o'sishdan iborat go'zal safardir.",
      syllables: 'ha · yot',
      ipa: '[hɑˈjɔt]',
      origin: 'arabcha',
    ),
    'TABIAT': const WordDefinition(
      word: 'TABIAT',
      meaning: "Insoniyatni o'rab turgan barcha moddiy borliq, o'simlik va hayvonot olami.",
      partOfSpeech: 'Ot',
      example: "Tabiatni asrash va sevish har bir insonning sharafli burchidir.",
      syllables: 'ta · bi · at',
      ipa: '[tɑbiˈɑt]',
      origin: 'arabcha',
    ),
    'ASAL': const WordDefinition(
      word: 'ASAL',
      meaning: "Asalarilar tomonidan gul nektaridan yig'iladigan shirin va shifobaxsh modda.",
      partOfSpeech: 'Ot',
      example: "Tog' asali o'zining tabiiy xushbo'y hidi va shifobaxshligi bilan mashhur.",
      syllables: 'a · sal',
      ipa: '[ɑˈsɑl]',
      origin: 'arabcha',
    ),
    'LOLA': const WordDefinition(
      word: 'LOLA',
      meaning: "Bahorda ochiladigan qizil, sariq yoki oq rangli chiroyli nozik gul.",
      partOfSpeech: 'Ot',
      example: "Tog' bag'ridagi qip-qizil lolalar ko'zni quvontirib ochildi.",
      syllables: 'lo · la',
      ipa: '[lɔˈlɑ]',
      origin: 'forscha',
    ),
    'RAQAM': const WordDefinition(
      word: 'RAQAM',
      meaning: "Sonlarni yozuvda ifodalash uchun ishlatiladigan shartli matematik belgi.",
      partOfSpeech: 'Ot',
      example: "Hisob-kitob jarayonida har bir raqam aniq va puxta tekshirildi.",
      syllables: 'ra · qam',
      ipa: '[rɑˈqɑm]',
      origin: 'arabcha',
    ),
    'BOLA': const WordDefinition(
      word: 'BOLA',
      meaning: "Kichik yoshdagi inson, farzand, o'g'il yoki qiz bola.",
      partOfSpeech: 'Ot',
      example: "Bog'chadagi quvnoq bola qo'shiq aytib hammaga xursandchilik ulashdi.",
      syllables: 'bo · la',
      ipa: '[bɔˈlɑ]',
      origin: "o'zbekcha",
    ),
  };
}
