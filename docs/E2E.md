# Word Battle — E2E supurmasi

**Sana:** 2026-08-10 · **Commit:** `c117ee4` · **Mashina:** Linux, Java 17.0.20,
Maven 3.9.9, Flutter 3.44.8 (Dart 3.12.2). Docker o'rnatilmagan.

Bu hujjat supurmaning o'zi emas — uning hisoboti. Uchta narsani aytadi: qaysi
yo'llar rostdan uchidan-uchiga sinaladi, qaysilari **sinalmaydi**, va bugun
yugurtirilganda nima chiqdi. Ikkinchi bo'lim eng qimmati: yashil natija faqat
o'zi qamragan narsa haqida gapiradi.

---

## Supurma nima

Alohida skript, harness yoki CI yo'q — `.github/workflows/` ham mavjud emas.
Supurma ikkita buyruqdan iborat va qo'lda yugurtiriladi:

```bash
cd backend && ./mvnw test     # 27 sinf, 113 test
flutter test                  # 11 fayl, 114 test
```

Ikkalasi bir-biridan mustaqil: birinchisi Maven va H2/PostgreSQL bilan, ikkinchisi
Flutter test bindingi bilan ishlaydi, qulflar urishmaydi — parallel yugurtirsa ham
bo'ladi.

---

## Nima qamrab olingan

### Server — `backend/src/test/java/uz/wordbattle/`

Serverning E2E qamrovi haqiqiy: `@SpringBootTest(webEnvironment = RANDOM_PORT)`
bilan server ko'tariladi, testlar unga haqiqiy `StandardWebSocketClient` bilan
ulanadi va REST'ni `TestRestTemplate` orqali chaqiradi. Ya'ni soket, handshake,
freym marshrutlash va ma'lumotlar bazasi — hammasi mock emas, o'zi.

| Yo'l | Qayerda sinaladi |
|---|---|
| Kirish, Google `idToken` tekshiruvi | `auth/GoogleAuthServiceTest`, `auth/JwtServiceTest` |
| REST yo'li: login → taxallus → do'stlik → reyting → profil | `ApiIntegrationTest` |
| Token bekor qilish (logout, akkaunt o'chirish, ko'p qurilma) | `auth/TokenRevocationTest` |
| Bekor qilingan token soket ocha olmasligi | `auth/RevokedTokenSocketTest` |
| Soket handshake — token `Authorization` header'ida | `match/InviteWebSocketTest` |
| Matchmaking oynasi, kengayishi va bot'ga o'tishi | `match/MatchmakingBandTest`, `match/DuelWebSocketTest` |
| Jang sikli: juftlanish, so'z rad etilishi, zanjir sinxroni, taslim, reyting | `match/DuelWebSocketTest` |
| Zanjir holati, harflar ketma-ketligi, kamyob harf ustidan qadam | `match/DuelSessionTest`, `match/RareLetterTrapTest` |
| Bitta o'yinchi uchun ikkita jang, parallel hisob-kitob, eskirgan taymer | `match/DuelServiceConcurrencyTest` |
| Natijasi yozilmagan jang baribir ikkala ekranda tugashi | `match/DuelFinishWithoutAResultTest` |
| Tashlab ketilgan jang natijasi keyingi jangni buzmasligi | `match/StaleDuelFinishTest` |
| Qayta ulanish ostida qolib ketgan natija baribir yetib borishi | `match/MissedFinishRaceTest` |
| Chaqiruv oqimi: yuborish, qabul, rad, muddat, navbatdan chiqish | `match/InviteWebSocketTest` |
| Qayta ulanish — soket uzildi, ilova tirik (grace, forfeit, ikkinchi soket) | `match/ReconnectWebSocketTest` |
| Qayta tiklash — ilova o'ldi va qaytadan ochildi | `match/DuelResumeWebSocketTest` |
| Glicko-2: g'alaba/mag'lubiyat, RD chegaralari, faolsizlikdan RD o'sishi | `rating/Glicko2Test` |
| Migratsiyalar V1→V6, mavjud bazani yangilash | `migration/MigrationChainTest` |
| Flyway sxemasi entity'larga mos kelishi | `migration/SchemaMatchesEntitiesTest` |
| Presence: soket yopilishi, qayta ochilishi, akkaunt o'chirilishi | `friend/PresenceWebSocketTest` |
| Do'stlik so'rovi poygasi, o'chirilgan do'st reytingda | `friend/DuplicateFriendRequestTest`, `leaderboard/FriendsLeaderboardTest` |
| Lug'at va bot javoblari | `dictionary/DictionaryServiceTest` |
| Taxallus qoidalari va takliflari | `user/NicknamePolicyTest` |
| Akkaunt o'chirish (jang o'rtasida ham) | `user/AccountDeletionTest` |
| Soketdagi freym cheklovi va jurnal toshqini | `ws/FrameRateLimiterTest` |
| `application.yml` qiymatlari kodadagi standartlarga mosligi | `config/ShippedConfigurationTest` |

### Ilova — `test/`

Ilova tomonida barcha testlar **birlik va vidjet** darajasida: har biri
serverdan keladigan freymni qo'lda yozilgan `Map` sifatida beradi yoki HTTP'ni
`MockClient` bilan almashtiradi. Haqiqiy serverga ulanadigan test yo'q.

| Nima sinaladi | Fayl |
|---|---|
| 27 ta ekranning 360×784dp da joylashuvi (+6 tasi klaviatura ochiq holda) | `layout_test.dart` |
| O'sha 27 ekranning PNG'ga renderi (maketga solishtirish uchun) | `screenshot_test.dart` |
| Chaqiruv poygasi: javob qaysi chaqiruvga tegishli, muddat hisobi | `invite_race_test.dart` |
| Jang ekranida matn maydoni, klaviatura, navbat, zanjir skrolli | `duel_input_test.dart` |
| Ilova o'ldi va qayta ochildi: bitta `duel.update` dan butun taxta | `duel_resume_test.dart` |
| Freym qaysi jangga tegishli (`duelFrameApplies`) | `duel_frame_test.dart` |
| API klienti: 401, xato kodlari, tarmoq uzilishi, token header'da | `api_client_test.dart` |
| Sessiya tiklash: token qachon saqlanadi, qachon unutiladi | `session_test.dart` |
| Navbatdan chiqish/qaytish ilova fon'ga ketganda | `queue_lifecycle_test.dart` |
| Birinchi ochilish onboarding'ga tushishi | `widget_test.dart` |
| Tab almashuvi animatsiyasi | `nav_transition_test.dart` |

---

## Nima qamrab olinmagan

### Eng jiddiy bo'shliq: ikkala supurmaning orasidagi chok

Server E2E'si haqiqiy soket bilan ishlaydi, lekin uning mijozi — **Java test
klienti**, Flutter ilovasi emas. Ilova testlari esa serverni qo'lda yozilgan
JSON bilan almashtiradi. Ya'ni **ilovaning jang yo'li hech qachon haqiqiy
serverga qarshi ishlatilmagan**, va ikkala supurma yashil bo'lishi ular
bir-biriga mos ekanini isbotlamaydi. Bu bitta bo'shliqning ikki tomoni:

**1. Server chiqaradigan JSON ilova o'qiydigan JSON'ga mosligini hech narsa
tekshirmaydi.** Server tomonda shakl — `match/DuelMessages.java` dagi
`record`'lar; ilova tomonda — `lib/api/duel_models.dart` dagi qo'lda yozilgan
`fromJson`. Ular hozir mos, lekin mosligini ushlab turadigan test yo'q.
`test/duel_resume_test.dart` dagi izoh buni ochiq aytadi: freym "server
yuboradigan shaklda aynan" deb qo'lda yozilgan — ya'ni ishonch, tekshiruv emas.

Yomon tomoni shundaki, mos kelmaslik **shovqinsiz** o'tadi: parserlar yo'q
maydonni `?? true` / `?? false` bilan to'ldiradi. Agar server `duel.update` dan
`rated` ni olib tashlasa, ilova uni `true` deb o'qiydi va reytingsiz bot jangida
reyting o'zgarishini ko'rsatadi — ikkala supurma yashil qolgan holda.

**2. `lib/api/game_socket.dart` umuman sinalmagan.** Hech bir test uni import
qilmaydi. Sinalmay qolgani — backoff jadvali (`[1, 2, 4, 8, 15]` soniya), 25
soniyalik heartbeat, va `_onFrame` ichidagi `_attempt = 0`. Oxirgisi ayniqsa
muhim: fayldagi izoh o'sha qatorsiz nima bo'lganini yozib qo'ygan — sessiyadagi
ikkinchi uzilish to'liq 15 soniya kutgan, bu serverning grace muddatidan uzun,
va o'yinchi yutayotgan jangini yo'qotgan. Tuzatilgan, lekin uni qo'riqlaydigan
test yo'q. Har bir jang shu sinf orqali o'tadi.

### Qolgan bo'shliqlar — avtomatlashtirilishi mumkin

Bular test yozilsa yopiladi, qurilma shart emas:

- **`duel.aborted`** — server o'chayotganda jonli janglarga yuboriladigan freym.
  Server tomonda ham, ilova tomonda ham sinalmagan. Bu nodir yo'l emas: har bir
  deploy'da o'sha paytdagi barcha janglar shu yerdan o'tadi.
- **`queue.leave`** — ilova yuboradi, server qabul qiladi, lekin bironta server
  testi uni yubormaydi. Ilova tomonda qaror (`queue_lifecycle_test.dart`)
  sinalgan, server tomonda qabul — yo'q.
- **`ping` / `pong` heartbeat** — hech bir testda yo'q, ya'ni butun aylanma
  sinalmagan.
- **Sinalmagan REST endpoint'lari:** `GET /api/practice/hints`,
  `GET /api/users/search`, `GET /api/matches/{id}`,
  `POST /api/friends/requests/{id}/decline`, `DELETE /api/friends/{userId}`.
- **Ekran yuklovchilari** — `app_root.dart` dagi `_loadBoard`, `_loadProfile`,
  `_loadHistory`, `_loadPractice`. Ekranlarning o'zi render qilinadi, lekin
  ularga ma'lumot keltiradigan kod hech qayerda chaqirilmaydi.
- **Google Sign-In ilova tomoni** (`lib/api/google_auth.dart`). Server tomondagi
  `idToken` tekshiruvi sinalgan, ilova o'sha token'ni qanday olishi — yo'q.

### Faqat qurilmada tekshiriladi

Bularni test bilan yopib bo'lmaydi — telefon kerak:

- **Profil / Reyting taxtasi / Tarix / Mashq ekranlari qurilmada hech
  ochilmagan.** Diqqat: ular `layout_test.dart` va `screenshot_test.dart` da
  render qilinadi, lekin **qo'lda yasalgan ma'lumot bilan**. Haqiqiy serverdan
  kelgan javob bilan, haqiqiy telefonda ochilmagan — yuqoridagi "ekran
  yuklovchilari" bo'shlig'i aynan shu yerda ko'rinadi.
- **Qayta ulanish (parvoz rejimi) real qurilmada sinalmagan.** Serverning yarmi
  `ReconnectWebSocketTest` bilan qoplangan; ilovaning yarmi — `GameSocket` —
  sinalmagan (yuqoriga qarang). Ikkalasi telefonda birga hech ishlamagan.
- **Odam-odamga jang telefonda o'ynalmagan.** Ikkita haqiqiy qurilma, ikkita
  haqiqiy hisob, boshidan oxirigacha.
- **Sovuq ishga tushish vaqti o'lchanmagan** — ilova 10 soniyada ochiladimi.
  Jang tiklash tuzatishi shunga bog'liq: server jangni faqat soket ulanganda
  qaytaradi, ilova esa `_bootstrap` → `_session.restore()` → `_connectSocket()`
  zanjiridan o'tadi. Bu zanjir sekin bo'lsa, o'yinchining navbat taymeri u
  taxtani ko'rgunicha tugaydi. Hech qanday test bu vaqtni o'lchamaydi.
- **Release build** — `flutter build appbundle --release` bilan yig'ilgan,
  imzolangan paket va undagi `usesCleartextTraffic="false"` cheklovi.

---

## Bugungi natija

Ikkala supurma ham yashil. Hech narsa yiqilmadi, hech narsa o'tkazib
yuborilmadi.

### `cd backend && ./mvnw test`

```
Tests run: 113, Failures: 0, Errors: 0, Skipped: 0
BUILD SUCCESS
Total time:  02:24 min      (real 2m25.491s)
```

27 sinf. Eng uzunlari — `DuelWebSocketTest` 48.56 s, `ReconnectWebSocketTest`
40.30 s, `PresenceWebSocketTest` 12.75 s, `RareLetterTrapTest` 8.82 s: ular
haqiqiy taymerlarni haqiqiy vaqtda kutadi.

| Sinf | Test | Vaqt |
|---|---|---|
| `dictionary/DictionaryServiceTest` | 11 | 0.098 s |
| `rating/Glicko2Test` | 10 | 0.018 s |
| `match/DuelSessionTest` | 9 | 0.013 s |
| `match/InviteWebSocketTest` | 9 | 0.959 s |
| `ApiIntegrationTest` | 8 | 0.359 s |
| `auth/JwtServiceTest` | 7 | 0.027 s |
| `auth/TokenRevocationTest` | 7 | 1.615 s |
| `auth/GoogleAuthServiceTest` | 6 | 1.495 s |
| `match/DuelWebSocketTest` | 4 | 48.56 s |
| `match/ReconnectWebSocketTest` | 4 | 40.30 s |
| `match/DuelServiceConcurrencyTest` | 4 | 0.367 s |
| `ws/FrameRateLimiterTest` | 4 | 0.611 s |
| `user/NicknamePolicyTest` | 4 | 0.008 s |
| `friend/PresenceWebSocketTest` | 3 | 12.75 s |
| `auth/RevokedTokenSocketTest` | 3 | 0.246 s |
| `match/DuelResumeWebSocketTest` | 3 | 4.233 s |
| `user/AccountDeletionTest` | 3 | 1.288 s |
| `match/MatchmakingBandTest` | 3 | 0.026 s |
| `migration/MigrationChainTest` | 2 | 1.872 s |
| `config/ShippedConfigurationTest` | 2 | 0.028 s |
| `migration/SchemaMatchesEntitiesTest` | 1 | 1.217 s |
| `friend/DuplicateFriendRequestTest` | 1 | 2.352 s |
| `match/MissedFinishRaceTest` | 1 | 3.902 s |
| `match/RareLetterTrapTest` | 1 | 8.824 s |
| `match/DuelFinishWithoutAResultTest` | 1 | 1.078 s |
| `match/StaleDuelFinishTest` | 1 | 2.112 s |
| `leaderboard/FriendsLeaderboardTest` | 1 | 0.087 s |

Migratsiya testlari bu mashinada **embedded PostgreSQL** da yurdi — Docker
topilmadi:

```
Could not find a valid Docker environment ... /var/run/docker.sock
No Docker daemon — migration tests are using an embedded PostgreSQL on port 45757
```

Testcontainers'ning bu xatosi jurnalda `ERROR` darajasida chiqadi, lekin bu
kutilgan holat: `MigrationDatabase` shundan keyin embedded serverga o'tadi va
testlar o'tadi.

### `flutter test`

```
00:08 +114: All tests passed!
real  0m12.994s
```

| Fayl | Test |
|---|---|
| `layout_test.dart` | 33 |
| `screenshot_test.dart` | 27 |
| `invite_race_test.dart` | 13 |
| `duel_input_test.dart` | 8 |
| `duel_resume_test.dart` | 8 |
| `api_client_test.dart` | 7 |
| `session_test.dart` | 6 |
| `duel_frame_test.dart` | 6 |
| `queue_lifecycle_test.dart` | 4 |
| `widget_test.dart` | 1 |
| `nav_transition_test.dart` | 1 |

Chiqishda bitta zararsiz ogohlantirish bor —
`A tag was used that wasn't specified in dart_test.yaml: screenshots`.
`screenshot_test.dart` `@Tags(['screenshots'])` bilan belgilangan, lekin repoda
`dart_test.yaml` yo'q. Test baribir yuradi.

---

## Supurmani qanday yugurtirish

```bash
# Server
cd backend
./mvnw test

# Ilova (repo ildizidan)
flutter test
```

**Talablar.** Java 17 va Flutter SDK. Maven o'rnatish shart emas — `./mvnw`
o'zi keltiradi.

**Ma'lumotlar bazasi.** Testlarning aksariyati H2 da `ddl-auto: create-drop`
bilan yuradi, hech narsa kerak emas. Faqat `MigrationChainTest` va
`SchemaMatchesEntitiesTest` haqiqiy PostgreSQL talab qiladi va uni o'zi
ko'taradi: Docker demoni bo'lsa Testcontainers (`postgres:16-alpine`), bo'lmasa
`io.zonky.test:embedded-postgres`. Ikkalasi ham topilmasa test **skip bo'lmaydi
— yiqiladi**, sababini aytib. Bu ataylab: ilgari ular Docker'siz jimgina skip
bo'lardi va yashil ro'yxatda o'tgandek ko'rinardi.

Faqat migratsiyalarni yugurtirish:

```bash
cd backend && ./mvnw test -Dtest='MigrationChainTest,SchemaMatchesEntitiesTest'
```

Faqat ekran rasmlarini yangilash (`build/screens/*.png`):

```bash
flutter test test/screenshot_test.dart
```

---

## Ma'lum cheklovlar

Bular supurmadagi testlarning o'zidagi cheklovlar — nima yashil bo'lganda ham
isbotlanmay qoladi:

- **`FrameRateLimiterTest.aFloodCostsTwoLogLinesHoweverLongItRuns` vaqtga
  bog'liq marjinga tayanadi.** Limit soniyasiga 2 freym, ya'ni yangi token 500
  ms da tiklanadi; test 500 ta chaqiruvni shu 500 ms ichida tugatishi kerak,
  keyin `Thread.sleep(600)` bilan kutadi. Juda band mashinada sikl 500 ms dan
  cho'zilsa, o'rtada token tiklanadi va hisob o'zgaradi. Bugun o'tdi, lekin bu
  mashinaning tezligiga bog'liq.

- **Migratsiya testlari embedded PostgreSQL da yurdi, prod Postgres da emas.**
  Bir xil major versiya (16), lekin bir xil server emas: sozlamalar, kengaytmalar
  va operator qo'lidagi rol/huquqlar boshqa. Docker bo'lgan mashinada esa
  `docker-compose.yml` dagi aynan o'sha image ishlatiladi — bu ishonchliroq.

- **Soket testlari haqiqiy vaqtni kutadi.** `DuelWebSocketTest` va
  `ReconnectWebSocketTest` birgalikda 89 soniya oladi, chunki forfeit grace va
  navbat taymerlari soat bo'yicha o'tadi. Ular sekin, lekin soxta soat bilan
  almashtirilsa aynan sinalayotgan narsa — vaqt — yo'qoladi.

- **H2 va prod Postgres farqi.** Migratsiya testlaridan boshqa hamma narsa H2 da
  yuradi va sxemani Hibernate entity'lardan quradi. SQL darajasidagi farqlar
  (qisman indekslar, `on conflict` xulqi, tip mosligi) faqat migratsiya
  testlarida ko'rinadi.

- **Ekran testlari bitta o'lchamda.** Hammasi 360×784dp (1080×2352, DPR 3).
  Boshqa ekran nisbatlari va tizim darajasidagi matn kattalashtirish
  (`textScaleFactor`) sinalmagan — ular aynan joylashuv buziladigan holatlar.
  Mavzu bunga kirmaydi: ilova bitta qat'iy qorong'i mavzuda ishlaydi
  (`main.dart`, `Brightness.dark`), tanlanadigan yorug' rejim yo'q.
