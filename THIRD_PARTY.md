# Uchinchi tomon materiallari

Bu repozitoriyda quyidagi tashqi materiallar qayta tarqatiladi.

## Shriftlar — SIL Open Font License 1.1

| Shrift | Muallif | Litsenziya |
|---|---|---|
| Space Grotesk | [Florian Karsten](https://github.com/floriankarsten/space-grotesk) | [OFL](assets/fonts/OFL-SpaceGrotesk.txt) |
| JetBrains Mono | [JetBrains](https://github.com/JetBrains/JetBrainsMono) | [OFL](assets/fonts/OFL-JetBrainsMono.txt) |

Ular `assets/fonts/` ichida — ilova internetsiz ham to'g'ri shrift bilan
ochilishi uchun (Google Fonts'dan yuklab olish o'rniga).

## So'z ro'yxatlari

| Fayl | Manba | Litsenziya |
|---|---|---|
| `backend/src/main/resources/words/valid-en.txt` | [dwyl/english-words](https://github.com/dwyl/english-words) | Unlicense (public domain) |
| `backend/src/main/resources/words/common-en.txt` | [google-10000-english](https://github.com/first20hours/google-10000-english) | public domain / CC-BY-SA-3.0 |

Birinchisi — o'yinchi so'zini qabul qilish uchun (~358 000 so'z), ikkinchisi —
bot tanlaydigan keng tarqalgan so'zlar (~8 000), shunda uning yurishlari
tabiiy ko'rinadi.

### Bu fayllarga kiritilgan o'zgarishlar

Ikkala fayl ham manbadan olingan holida qoldirilgan — hech bir qatori
o'chirilmagan yoki tahrirlanmagan, shunda ularni kelajakda yangilash oson
bo'ladi. Ular ikkita o'zimiz tuzgan ro'yxat orqali filtrlanadi, filtrlash
`DictionaryService` yuklanish paytida bajariladi:

| Fayl | Nima qiladi |
|---|---|
| `backend/src/main/resources/words/invalid-en.txt` | 872 ta uch harfli yozuv (`aaa`, `cpu`, `faq`, `dwt`) — ular hech qayerda qabul qilinmaydi |
| `backend/src/main/resources/words/bot-excluded-en.txt` | 888 ta atoqli ot va qisqartma (`aaron`, `london`, `blvd`) — faqat bot o'ynay olmaydi, o'yinchi ayta oladi |

Bu ikkalasi — bizning ishimiz, tashqi material emas. Har birining boshida
qanday qoida bilan tuzilgani yozilgan. Tuzishda quyidagi ro'yxatlar solishtirish
uchun ishlatilgan (ularning o'zi repozitoriyga qo'shilmagan):

| Ro'yxat | Litsenziya |
|---|---|
| [ENABLE](https://github.com/dolph/dictionary) | public domain |
| SOWPODS / Collins Scrabble Words | — |
| [hunspell en_US](https://github.com/wooorm/dictionaries) (SCOWL asosida) | MIT / SCOWL litsenziyasi |

## Kutubxonalar

Flutter tomonda `pubspec.yaml`, server tomonda `backend/pom.xml` — barchasi
o'z litsenziyalari ostida (asosan Apache-2.0 va BSD).
