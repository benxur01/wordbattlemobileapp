# Word Battle — backend

Realtime 1v1 English word-chain server for the Word Battle app.
Java 17 · Spring Boot 3.5 · PostgreSQL · WebSocket · Glicko-2.

Every rule that decides a duel lives here: the turn timer, word validation,
who won and what it did to the ratings. The app only renders what the server
sends — a modified client can send whatever it likes and gets a rejection.

---

## Ishga tushirish

### Docker (tavsiya etiladi)

```bash
cp .env.example .env
# .env ichida JWT_SECRET ni to'ldiring:  openssl rand -base64 48
docker compose up --build
```

API: `http://localhost:8080` · WebSocket: `ws://localhost:8080/ws?token=…`

### Lokal (o'zingizdagi Postgres bilan)

```bash
createdb wordbattle
export DB_URL=jdbc:postgresql://localhost:5432/wordbattle
export DB_USER=wordbattle DB_PASSWORD=wordbattle
export JWT_SECRET="$(openssl rand -base64 48)"
export DEV_LOGIN_ENABLED=true          # faqat ishlab chiqish uchun

./mvnw spring-boot:run
```

Testlar:

```bash
./mvnw test
```

Hech narsa o'rnatish shart emas. Testlarning aksariyati H2 da ishlaydi;
migratsiya testlariga haqiqiy PostgreSQL kerak va u o'zi ko'tariladi — Docker
bo'lsa Testcontainers, bo'lmasa ichki (embedded) server. Pastdagi
[Testlar](#testlar) bo'limiga qarang.

---

## Konfiguratsiya

| Env | Nima uchun | Standart |
|---|---|---|
| `DB_URL`, `DB_USER`, `DB_PASSWORD` | PostgreSQL ulanishi | `localhost:5432/wordbattle` |
| `JWT_SECRET` | Tokenlarni imzolash. **Kamida 32 bayt. Standart qiymat yo'q** — berilmasa server ko'tarilmaydi | — |
| `SPRING_PROFILES_ACTIVE` | Prodda `prod` qiling: shunda namunaviy yoki bo'sh `DB_PASSWORD` bilan server ko'tarilmaydi (`DatabasePasswordGuard`) | bo'sh |
| `CORS_ALLOWED_ORIGINS` | Brauzer origin'lari (vergul bilan). Bo'sh bo'lsa CORS umuman yo'q — telefon ilovasiga kerak emas | bo'sh |
| `TIME_ZONE` | Streak va kunlik so'z qaysi kun bo'yicha almashadi | `Asia/Tashkent` |
| `WS_FRAMES_PER_SECOND` / `WS_FRAME_BURST` | Soketdagi freym cheklovi (bitta o'yinchiga) | `20` / `40` |
| `JWT_TTL` | Token amal qilish muddati (ISO-8601) | `P30D` |
| `GOOGLE_WEB_CLIENT_ID` | Google **Web** OAuth client ID; bo'sh bo'lsa Google login o'chadi | bo'sh |
| `DEV_LOGIN_ENABLED` | `/api/auth/dev` ni yoqadi — **prodda hech qachon** | `false` |
| `ADMIN_BOOTSTRAP_USER_ID` | Startda shu `users.id` ga admin roli beriladi — birinchi adminni yaratishning yagona yo'li. Bo'sh bo'lsa hech kimga berilmaydi | bo'sh |
| `PORT` | HTTP porti | `8080` |

O'yin qoidalari `application.yml` dagi `wordbattle.duel` va
`wordbattle.matchmaking` bo'limlarida: navbat 15 s, so'z kamida 3 harf,
9 ta so'z — g'alaba, chaqiruv 12 s da so'nadi.

---

## Autentifikatsiya

1. Ilova Google Sign-In'dan `idToken` oladi va uni `/api/auth/google` ga yuboradi.
2. Server imzoni Google'ning ochiq kalitlari bilan tekshiradi (RS256, JWK set
   keshlanadi), `iss` va `aud` (Web client ID) ni solishtiradi, muddati
   o'tganini rad etadi, so'ng JWT qaytaradi.
3. Barcha keyingi so'rovlar: `Authorization: Bearer <token>`.
   WebSocket ham xuddi shu header bilan ulanadi — token URL'ga tushsa, u proxy
   va balanser loglarida qolib ketadi. Brauzer WS handshake'ida header qo'ya
   olmagani uchun `?token=<jwt>` shakli ham qabul qilinadi (faqat web build).

Token yaroqsiz bo'lsa API `401` qaytaradi — ilova shu holatda foydalanuvchini
onboarding'ga qaytarishi kerak.

### Tokenni bekor qilish

Har bir token `gen` da chiqarilgan paytdagi `users.token_generation` ni olib
yuradi, va har bir so'rovda shu raqam qatordagisi bilan solishtiriladi:

- `POST /api/auth/logout` hisoblagichni bittaga oshiradi → o'sha akkauntning
  **barcha** tokenlari o'sha zahoti o'ladi (tokenning o'ziga emas, akkauntga
  bog'langan — bir qurilmadan chiqish hammasidan chiqaradi);
- akkaunt o'chirilganda hisoblagich umuman o'qilmaydi (`deleted_at is not
  null`), demak o'chirilgan akkauntning tokeni ham o'lik;
- akkaunt bloklanganda ham xuddi shunday (`banned_at is not null`) — ban
  o'sha zahoti kuchga kiradi, tokenning muddati kutilmaydi va soket ham
  ochilmaydi;
- tekshiruv `JwtService.userIdFrom` ichida — REST filtri ham, WebSocket
  handshake'i ham shu yerdan o'tadi, ya'ni bekor qilingan token soket ocha
  olmaydi.

Muddati o'tgan yoki buzilgan token avvalgidek `401`. Hisoblagich xotirada emas,
`users` jadvalida: server qayta ishga tushganda unutiladigan bekor qilish —
bekor qilish emas.

**V6 dan oldin chiqarilgan tokenlarda `gen` yo'q va ular rad etiladi** — shu
migratsiyadan keyin hamma bir marta qaytadan kiradi.

---

## REST API

Barchasi `/api` ostida. `*` — token talab qilinmaydi.

### Auth
| Method | Path | Izoh |
|---|---|---|
| POST\* | `/auth/google` | `{idToken}` → `{token, user, needsNickname}` |
| POST\* | `/auth/dev` | `{displayName}` — faqat `DEV_LOGIN_ENABLED=true` |
| POST\* | `/auth/logout` | akkauntning barcha tokenlarini bekor qiladi — har doim `204`, tokensiz chaqirilsa hech nima qilmaydi |

### Foydalanuvchi
| Method | Path | Izoh |
|---|---|---|
| GET | `/users/me` | joriy profil (qisqa shakl) |
| GET | `/users/nickname/check?value=` | `{available, reason, suggestions[]}` — onboarding maydoni uchun |
| PUT | `/users/me/nickname` | `{nickname}` → band bo'lsa `409 nickname_taken` |
| PUT | `/users/me/city` | `{city}` |
| GET | `/users/me/profile` | statistika, 30 kunlik reyting grafigi, 8 ta nishon |
| GET | `/users/{id}/profile` | boshqa o'yinchi profili |
| GET | `/users/search?q=` | taxallus bo'yicha qidiruv |
| DELETE | `/users/me` | akkauntni o'chirish — `204`, token shu zahoti o'lik |

### Do'stlar
| Method | Path | Izoh |
|---|---|---|
| GET | `/friends` | onlayn/oflayn holati bilan |
| GET | `/friends/requests` | kelgan takliflar (+ umumiy do'stlar soni) |
| GET | `/friends/requests/count` | pastki paneldagi nishoncha uchun |
| POST | `/friends/requests` | `{userId}` — qarama-qarshi so'rov bo'lsa avtomatik qabul qilinadi |
| POST | `/friends/requests/{id}/accept` · `/decline` | |
| DELETE | `/friends/{userId}` | do'stlikni bekor qilish |

### Janglar
| Method | Path | Izoh |
|---|---|---|
| GET | `/matches?limit=` | tugagan janglar ro'yxati (raqib, natija, delta, sabab) |
| GET | `/matches/{id}` | bitta jangning to'liq zanjiri |

### Reyting va mashq
| Method | Path | Izoh |
|---|---|---|
| GET | `/leaderboard/global?limit=` | `{rows[], me}` — pastdagi "sizning o'rningiz" qatori bilan |
| GET | `/leaderboard/friends` | o'zi va do'stlari orasida |
| GET | `/practice/word` | kunlik so'z: `{word, ipa, meaning}` |
| GET | `/practice/hints?letter=&limit=` | "?" tugmasi uchun maslahatlar |
| GET | `/themes` | mavzuli bot jangi uchun `[{id, name}]` — server build'i bilan birga o'zgaradi, shuning uchun soket emas, REST |

### Turnirlar

Pulsiz, admin tomonidan boshqariladigan yagona eliminatsiya turnirlari — o'z
ro'yxatdan o'tish yo'q, hech qanday to'lov yo'q. `GET /{id}` istisno: u boshqa
har qanday tizimga kirgan foydalanuvchi uchun ham ochiq — bracket tomosha
qilish uchun, qatnashchi bo'lish shart emas.

| Method | Path | Izoh |
|---|---|---|
| GET | `/tournaments/active` | hozir o'ynalayotgan turnirlar — lobbi kartochkasi uchun |
| GET | `/tournaments/{id}` | to'liq bracket: barcha bosqichlar, har bir jangning holati va g'olibi |
| GET | `/tournaments/mine` | javobsiz takliflar va boshlashga tayyor janglar — jonli soket kadrining REST zaxira nusxasi |
| POST | `/tournaments/{id}/accept` · `/decline` | faqat shu taklifning egasi uchun |
| POST | `/tournaments/{id}/cancel` | faqat tashkilotchi uchun — o'zi tashkil qilgan turnirni bekor qiladi |

Har bir turnir tashqariga `https://<production-domain>/t/<id>` ko'rinishidagi
havola sifatida ulashilishi mumkin (native share sheet, `organize_tournament_manage_screen.dart`
va `tournament_bracket_screen.dart`dagi ulashish tugmasi). Android'da bu havola
App Links orqali ilovani to'g'ridan-to'g'ri o'sha turnirning bracketiga ochadi —
buning uchun `wordbattle.example.uz` haqiqiy domenga almashtirilishi va
`static/.well-known/assetlinks.json` dagi `sha256_cert_fingerprints`
o'rinbosari release keystore'dan olingan haqiqiy barmoq iz bilan
to'ldirilishi kerak (`keytool -list -v -keystore <keystore yo'li> | grep
SHA256` — keystore'ning o'zi qanday yaratilishi uchun ildiz papkadagi
[`README.md`](../README.md#release-imzosi)dagi "Release imzosi" bo'limiga
qarang). iOS'da esa hozircha
Universal Links yo'q (Apple Developer akkaunti yo'q), shuning uchun havola
oddiy brauzerda ochiladi.

### Admin panel

Hammasi `/admin` ostida va faqat `users.is_admin = true` bo'lgan akkaunt uchun.
Boshqa har qanday token — `403 forbidden`, tokensiz — `401`. Birinchi admin
faqat `ADMIN_BOOTSTRAP_USER_ID` orqali paydo bo'ladi (yuqoridagi jadval).

| Method | Path | Izoh |
|---|---|---|
| GET | `/admin/users?q=&page=&size=` | taxallus, ism yoki id bo'yicha qidiruv; o'chirilgan va bloklangan akkauntlar ham ko'rinadi |
| GET | `/admin/users/{id}` | profil, statistika, ban holati |
| POST | `/admin/users/{id}/ban` | `{reason}` (ixtiyoriy) — jangdan va soketdan chiqaradi, barcha tokenlarini o'ldiradi |
| POST | `/admin/users/{id}/unban` | |
| PUT | `/admin/users/{id}/nickname` | `{nickname}` — onboarding bilan bir xil qoidalar |
| GET | `/admin/matches?page=&size=` | barcha janglar (hech kimga bog'lanmagan) |
| GET | `/admin/metrics` | foydalanuvchilar, banlanganlar, bugungi janglar, bot/inson |
| GET | `/admin/audit-log?page=&size=` | har bir o'zgarish — kim, kimga, qachon |
| POST | `/admin/tournaments` | `{name, size}` — `size` 4/8/16/32 bo'lishi shart |
| GET | `/admin/tournaments?page=&size=` | barcha turnirlar |
| GET | `/admin/tournaments/{id}` | qatnashchilar ro'yxati + (boshlangan bo'lsa) bracket |
| POST | `/admin/tournaments/{id}/invite` | `{userId}` — `/users/search` orqali topilgan o'yinchini taklif qiladi |
| POST | `/admin/tournaments/{id}/start` | qabul qilganlar soni `size` ga teng bo'lgandagina ishlaydi; reyting bo'yicha seed qiladi va 1-bosqichni boshlaydi |
| POST | `/admin/tournaments/{id}/cancel` | istalgan turnirni bekor qiladi (tugagan yoki allaqachon bekor qilinganidan tashqari) |

Har bir o'zgartirish `admin_audit_log` ga o'zgarishning **o'zi bilan bitta
tranzaksiyada** yoziladi. Hech narsa o'zgarmagan bo'lsa (masalan, allaqachon
bloklangan akkauntni qayta bloklash) yozuv ham qo'shilmaydi.

Xatolar bir xil shaklda: `{"code": "...", "message": "...", "timestamp": "..."}`.

---

## WebSocket protokoli

Ulanish: `ws://host/ws?token=<jwt>`. Har bir kadr —
`{"type": "...", "payload": {...}}`.

### Mijoz → server

| type | payload | Nima qiladi |
|---|---|---|
| `queue.join` | — | raqib qidirishni boshlaydi |
| `queue.leave` | — | qidiruvni bekor qiladi |
| `queue.bot` | `{rating, theme?}` | qidiruvsiz bot jangi: reyting 200–2000 ga qisiladi, `theme` — `GET /api/themes` dagi id (bo'lmasa to'liq lug'at, notanish id — `unknown_theme` xatosi) |
| `duel.submit` | `{word}` | so'z yuboradi |
| `duel.forfeit` | — | jangdan chiqadi (mag'lubiyat) |
| `duel.power_up` | `{type}` | kuchaytirgichni sarflaydi: `add_time` (+10 s), `skip_letter`, `hint`, `pressure`. Faqat bot bilan mashqda va faqat o'z navbatida; har biri jangda bir marta. Rad javoblari: `not_a_bot_duel`, `not_your_turn`, `power_up_spent`, `unknown_power_up` |
| `duel.chat` | `{text}` | raqibga matn yuboradi (jang davomida, saqlanmaydi) |
| `duel.reaction` | `{emoji}` | tayyor emoji ro'yxatidan biri: 🔥😂👏😮🤝😢 |
| `invite.send` | `{userId}` | do'stni jangga chaqiradi |
| `invite.accept` / `invite.decline` | `{inviteId}` | chaqiruvga javob |
| `tournament.accept` / `tournament.decline` | `{tournamentId}` | turnir taklifiga javob |
| `tournament.match_start` | `{tournamentMatchId}` | tayyor turnir jangini boshlaydi — ikkala tomondan biri bossa yetarli |
| `team_invite.send` | `{userId}` | do'stni jamoa tuzishga chaqiradi (2v2) |
| `team_invite.accept` / `team_invite.decline` | `{inviteId}` | jamoa taklifiga javob |
| `team.cancel` | — | tuzilgan (hali navbatga qo'yilmagan yoki qo'yilgan) jamoani tarqatadi |
| `team.queue.join` / `team.queue.leave` | — | jamoa nomidan raqib jamoa qidirishni boshlaydi/bekor qiladi — ikkala a'zodan biri yuborsa kifoya |
| `team_duel.submit` | `{word}` | 2v2 jangida so'z yuboradi |
| `team_duel.forfeit` | — | 2v2 jangdan chiqadi (jamoasi mag'lub bo'ladi) |
| `team_duel.chat` | `{text}` | qolgan uch ishtirokchiga matn yuboradi (jang davomida, saqlanmaydi) |
| `team_duel.reaction` | `{emoji}` | `duel.reaction` bilan bir xil emoji ro'yxati, qolgan uch ishtirokchiga |
| `ping` | — | `pong` qaytadi |

### Server → mijoz

| type | Muhim maydonlar |
|---|---|
| `hello` | `user`, `rules{turnSeconds,minWordLength,wordsToWin,inviteTimeoutSeconds}`, `onlineCount`, `pendingFriendRequests` |
| `queue.joined` / `queue.left` | — |
| `match.found` | `duelId, opponent, rated, theme?, yourTurn, seedWord, needLetter, substitutedFrom?, turnSeconds, chain[]` |
| `duel.update` | `opponent, rated, theme?, chain[{word,mine,spentMs}], yourTurn, needLetter, substitutedFrom?, substitutionReason?, timeLeftMs, yourWords, opponentWords, opponentThinking` |
| `duel.rejected` | `code, message` — **navbat yo'qolmaydi**, faqat xato ko'rsatiladi |
| `duel.power_up` | `type, words[]` — kuchaytirgich sarflandi (tugma o'chadi); `words` faqat `hint` da to'la |
| `duel.finished` | `result(win/lose), reason, rated, delta, ratingBefore, ratingAfter, chainLength, yourWords, averageMs, newWords, streakDays, stuckLetter, hints[]` |
| `duel.chat` | `text` — raqibdan kelgan xabar |
| `duel.reaction` | `emoji` — raqibning reaksiyasi |
| `invite.sent` / `invite.incoming` / `invite.declined` / `invite.expired` | `inviteId`, `from`/`to`, `expiresInSeconds` |
| `duel.aborted` | `duelId, message` — server o'chmoqda, jang hech kimning foydasiga tugamadi |
| `tournament.invite` | `tournamentId, name, size, participantStatus` — ulanganda va qayta ulanganda, javobsiz taklif bo'lsa |
| `tournament.match_ready` | `tournamentMatchId, tournamentId, tournamentName, round, totalRounds, opponent` — ikkala joy ham to'lganda |
| `tournament.bracket_update` | `tournamentId` — bracket o'zgardi, ochiq bo'lsa mijoz `GET /tournaments/{id}` bilan qayta yuklaydi |
| `tournament.cancelled` | `tournamentId, name` — turnir bekor qilindi (tashkilotchi yoki admin tomonidan) |
| `team_invite.sent` / `team_invite.incoming` / `team_invite.declined` / `team_invite.expired` | `inviteId`, `from`/`to`, `expiresInSeconds` |
| `team.formed` | `teamId, partner` — ikkala a'zoga ham, taklif qabul qilinganda |
| `team.disbanded` | `teamId, reason` (`cancelled`/`disconnected`/`stale`) — jamoa tarqatilganda, boshqa a'zoga |
| `team.queue.joined` / `team.queue.left` | `since` / — |
| `team_duel.match_found` | `duelId, partner, opponentOne, opponentTwo, rated, yourTurn, turnPlayerId, seedWord, needLetter, substitutedFrom?, turnSeconds, chain[]` |
| `team_duel.update` | `chain[{word,playerId,mine,ally,spentMs}], yourTurn, turnPlayerId, needLetter, substitutedFrom?, timeLeftMs, yourWords, partnerWords, opponentOneWords, opponentTwoWords` |
| `team_duel.rejected` | `code, message` — `duel.rejected` bilan bir xil kodlar |
| `team_duel.finished` | `result(win/lose), reason, delta, ratingBefore, ratingAfter, chainLength, yourWords, averageMs, newWords, streakDays, stuckLetter, hints[], partner, opponentOne, opponentTwo` |
| `team_duel.chat` | `playerId, text` — to'rttadan qaysi biri yozgani `playerId` bilan aytiladi |
| `team_duel.reaction` | `playerId, emoji` — kim reaksiya qilgani `playerId` bilan aytiladi |
| `team_duel.aborted` | `duelId, message` — server o'chmoqda |
| `error` | `code, message` |

`duel.rejected` kodlari: `letters_only`, `too_long`, `too_short`,
`wrong_letter`, `already_used`, `not_a_word`, `off_theme` (faqat mavzuli
janglarda — so'z lug'atda bor, lekin mavzuga kirmaydi), `not_your_turn`.

Uzilish = mag'lubiyat: soket yopilsa server jangni raqib foydasiga tugatadi
(aks holda simni sug'urish bepul qochish yo'li bo'lardi). Qayta ulanganda
server jangning joriy holatini o'zi yuboradi.

### 2v2 ("jamoa") rejimi

1v1 bilan bir qatorda, unga hech narsani o'zgartirmasdan qo'shilgan alohida
rejim: ikki juft do'st jamoa tuzadi (`team_invite.*`), navbatga qo'yiladi
(`team.queue.join` — buni ikkala a'zodan biri yuborsa kifoya, ikkalasi ham
navbatga tushadi), va ikkita jamoa topilganda 4 kishilik janga tushadi.

Navbat qat'iy aylanma tartibda: **A-jamoa 1-a'zosi → B-jamoa 1-a'zosi →
A-jamoa 2-a'zosi → B-jamoa 2-a'zosi**, so'ng yana boshidan. "1-a'zo" — taklifni
yuborgan, "2-a'zo" — uni qabul qilgan o'yinchi; qaysi jamoa "A" bo'lishi
o'zboshimchalik bilan — navbatga birinchi qo'yilgan jamoa. So'z zanjiri qoidasi
1v1 bilan aynan bir xil (kamdan-kam harflar, taymer, lug'at) — farqi shuki,
kimdir navbatini yutqazsa (vaqt tugashi, taslim bo'lish), butun jamoasi
mag'lub bo'ladi, faqat o'sha o'yinchi emas.

Reyting: har bir o'yinchi alohida, Glicko-2 orqali, lekin **haqiqiy shaxs
emas, balki qarama-qarshi jamoaning ikkala a'zosining reytingi/og'ish
o'rtachasidan tuzilgan "virtual raqib"ga qarshi** hisoblanadi. 2v2 janglari
hozircha har doim reytingli — botga tushish yoki reytingsiz rejim yo'q.
Jamoa tuzish va navbat xotirada saqlanadi (1v1dagi kabi); faqat yakuniy
natija (`team_matches`, `team_match_words`) bazaga yoziladi.

---

## Qanday ishlaydi

**Raqib qidirish.** Navbatdagi o'yinchi ±75 reyting oynasi bilan boshlaydi,
oyna har 3 soniyada 40 ga kengayadi va 33-soniyada maksimumga (±500) yetadi.
35 soniyada odam topilmasa — bot bilan jang boshlanadi. Bu ikki raqam bir-biriga
bog'liq: oyna maksimumga botdan oldin yetmasa, maksimum qog'ozda qolib ketadi —
avval shunday edi va reytingi 325 ball farq qiladigan ikki o'yinchi bir vaqtda
navbatda turib ham botga tushgan. Bot janglari reytingsiz, ya'ni bunday juftlik
o'zini ajratgan farqni yopa ham olmaydi.

**Bot janglari reytingsiz.** Ular kutish ekranida qotib qolmaslik uchun bor;
reyting bersa, ladderni bot ustidan yig'ish juda oson bo'lardi. Streak,
statistika va o'rganilgan so'zlar esa hisobga olinadi (`rated: false`).

**So'z tekshiruvi.** ~357 700 so'zli ro'yxat serverda (`words/valid-en.txt`),
bot esa ~7 350 keng tarqalgan so'zdan tanlaydi, shunda uning yurishlari tabiiy
ko'rinadi. Ikkala ro'yxat ham yuklanish paytida filtrlanadi — qisqartmalar
hammadan, atoqli otlar esa bot pulidan olib tashlanadi (`THIRD_PARTY.md`).

**Mavzuli janglar.** Bot bilan jangda o'yinchi mavzu tanlashi mumkin
(`GET /api/themes` → `queue.bot {"rating": N, "theme": "animals"}`). Shunda
butun jang shu mavzuning ro'yxati ichida o'ynaladi: o'yinchining so'zi ham
(`off_theme` rad javobi), botning yurishi ham. Mavzu qiyinlik o'rnini
egallamaydi — ro'yxat `common-en.txt` bo'yicha ikkiga bo'linadi, shuning
uchun kuchli bot o'sha mavzuning kamroq uchraydigan, uzunroq so'zlarini
o'ynaydi. Mavzu faqat shu yo'lda bor: odam bilan odam jangi va navbat
o'zgarmagan. Ro'yxatlar `words/theme-*-en.txt` — har biri 300–450 so'z va
har biri `valid-en.txt` ning ichki qismi.

**Nodir harflar.** Zanjir `x` yoki `z` ga tugasa, keyingi so'z oxirgi emas,
undan oldingi harf bilan boshlanadi (`wax` → `a`). Sabab ingliz tilining
o'zida: `x` ga mingga yaqin so'z tugaydi, bot pulida esa `x` bilan
boshlanadigani bittagina — `xerox`, u ham `x` ga tugaydi. Oddiy qoida bilan bu
ikki yurishlik tuzoq bo'lardi — arzon majburlanadi, chiqib bo'lmaydi, va odam
raqib ham xuddi shunday qotib qoladi. Harflar ro'yxati sozlanadi
(`wordbattle.duel.rare-letters`); almashtirish yuz berganda kadrda
`substitutedFrom` keladi va ilova duel ekranida bir qatorlik izoh chiqaradi.

Mavzuli jangda shu ro'yxatga o'sha mavzu javob bera olmaydigan harflar ham
qo'shiladi (odatda `y`, `q`, `u` — `DictionaryService.thinLetters`). Sabab bir
xil: 358 ming so'zli lug'at bitta yupqa harfni ko'taradi, uch yuz so'zli mavzu
esa ko'tarmaydi — `battery` dan keyin butun mavzuda bitta `y` so'zi qolsa, u
o'ynalgan zahoti zanjir tugab qoladi. Shuning uchun mavzudagi so'z
o'chirilmaydi, harf `x` bilan bir qatorda o'tkazib yuboriladi.

**Kuchaytirgichlar.** Faqat bot bilan mashqda, to'rttasi bor va har biri
jangda bir marta ishlatiladi (`duel.power_up`): `add_time` navbatga 10 soniya
qo'shadi (server taymerni ham qayta qo'yadi, ekrandagi raqam bilan cheklanib
qolmaydi), `skip_letter` joriy harfni rad etadi va zanjir undan oldingi harfga
o'tadi (nodir harf qoidasining o'zi, faqat o'yinchi bosgani —
`substitutionReason: "power_up"`), `hint` shu harfga mos uchta so'z ko'rsatadi
(mavzuli jangda mavzu ichidan), `pressure` esa botning **keyingi** javobini
1,2–2,4 s o'rniga 0,3–0,6 s ichida qaytaradi. Bot uchun "vaqt" shundan iborat:
uning soati yo'q, javobni darrov topadi va shunchaki kutib turadi — shuning
uchun bu kuchaytirgich botni jazolamaydi, o'yinchini tezroq raqibga o'rgatadi.
Reytingli jangda (odam bilan odam, 2v2, turnir) kuchaytirgich umuman yo'q:
server har qanday `duel.power_up` ni `not_a_bot_duel` bilan rad etadi. Hech
narsa bazaga yozilmaydi — zaryad jang bilan tug'iladi va jang bilan ketadi.

**Reyting.** Glicko-2 (rating / deviation / volatility), har jang — bitta
davr. Yangi o'yinchi tez, tajribalisi sekin harakatlanadi.

**"Yangi so'z" hisobi.** `user_words` jadvali har bir o'yinchi o'ynagan
so'zlarni eslab qoladi, shuning uchun g'alaba ekranidagi son haqiqiy.

---

## Ma'lumotlar bazasi

Flyway migratsiyalari `src/main/resources/db/migration`:

- `users` — profil, Glicko-2 ko'rsatkichlari, statistika, streak,
  `token_generation` (chiqishda oshadi — yuqoriga qarang)
- `friendships` (har yo'nalish uchun bitta qator), `friend_requests`
- `matches`, `match_words` — jang tarixi va zanjir
- `rating_history` — profil grafigi uchun
- `practice_words`, `user_words`
- `admin_audit_log` — admin panelidagi har bir o'zgarish (`users.is_admin` va
  `users.banned_at` bilan birga V9 da qo'shilgan)
- `tournaments`, `tournament_participants`, `tournament_matches` — pulsiz
  yagona eliminatsiya turnirlari (V11). Bracketning har bir bosqichi va slot'i
  turnir boshlanganda bir vaqtda yaratiladi, shuning uchun butun tuzilma
  1-bosqichdanoq ma'lum — keyingi bosqichlar faqat o'yinchi maydonini to'ldiradi.

Taxalluslar registrga bog'liq bo'lmagan holda unikal: `lower(nickname)`
ustidagi unikal indeks. Ikki o'yinchi bir vaqtda bir nomni so'rasa, biri
`409` oladi.

---

## Prodga chiqarishdan oldin

1. `JWT_SECRET` va `GOOGLE_WEB_CLIENT_ID` ni to'ldiring, `DEV_LOGIN_ENABLED=false`.
   (Sirsiz server ataylab ko'tarilmaydi.)
2. `SPRING_PROFILES_ACTIVE=prod` qiling va `DB_PASSWORD` ga haqiqiy parol
   bering (`openssl rand -base64 24`). `prod` profilida namunaviy `wordbattle`
   paroli bilan server ataylab ko'tarilmaydi — u shu repozitoriyda yozilgan.
3. HTTPS/WSS terminatsiyasi (nginx yoki cloud LB) qo'ying — ilova release
   build'da cleartext HTTP'ni umuman rad etadi.
4. Postgres uchun zaxira nusxa (backup) sozlang.
5. `/actuator/health/readiness` va `/liveness` ni monitoringga ulang.

**Miqyoslash haqida.** Hozirgi versiya bitta instansiya uchun: navbat, onlayn
holat va faol janglar xotirada saqlanadi. Bir nechta nusxa ishga tushirish
kerak bo'lganda `MatchmakingService`, `PresenceService` va `SocketRegistry` ni
Redis'ga ko'chirish kifoya — qolgan mantiq o'zgarmaydi.

---

## Testlar

```bash
./mvnw test
```

- `Glicko2Test` — reyting matematikasi (g'olib ko'tariladi, kuchli raqib
  ustidan g'alaba qimmatroq, deviation chegaralari)
- `NicknamePolicyTest` — taxallus qoidalari va takliflar
- `GoogleAuthServiceTest` — Google imzolagan `idToken` qabul qilinadi;
  boshqa ilova uchun berilgani, o'zgartirilgani va eskirgani rad etiladi
- `JwtServiceTest` — sirsiz yoki namunaviy sir bilan server ko'tarilmasligi
- `DuelSessionTest` — zanjir holati va harflar ketma-ketligi
- `ApiIntegrationTest` — login → taxallus → do'stlik → reyting yo'li
- `DuelWebSocketTest` — ikkita haqiqiy mijoz: juftlanish, noto'g'ri so'zlarning
  rad etilishi, zanjirning sinxronligi, taslim bo'lish va reyting hisobi;
  alohida test bot bilan jangni tekshiradi

### Migratsiya testlari

Yuqoridagilarning hammasi H2 da `ddl-auto: create-drop` bilan ishlaydi: sxemani
entity'lardan Hibernate quradi, `db/migration` fayllari esa umuman ochilmaydi.
Prodda teskarisi — sxemani Flyway quradi, Hibernate faqat `validate` qiladi.
Ya'ni H2 suite'i migratsiyalar haqida hech narsa isbotlamaydi, ular esa
birinchi marta prodda ishga tushadi va yiqilsa server umuman ko'tarilmaydi.

Shu bo'shliqni ikkita test yopadi. Ikkalasi bitta haqiqiy PostgreSQL 16 ni
bo'lishadi (`MigrationDatabase`):

- `MigrationChainTest` — bo'sh sxemada V1→V16 zanjiri to'liq bajarilishi
  (`baseline-on-migrate: true` V1 ni tashlab ketmasligi ham shu yerda),
  qisman indekslar predikati bilan saqlanishi, qayta `migrate` bo'sh amal
  bo'lishi. Ikkinchi test — **mavjud bazani yangilash**: V2 da ma'lumot
  solinadi, so'ng V3 ustunni tashlaydi, V5 va V6 esa to'la jadvalga `not null`
  ustun qo'shadi. Noldan yaratish bu yo'lni umuman tekshirmaydi.
- `SchemaMatchesEntitiesTest` — server aynan proddagi juftlik bilan ko'tariladi:
  Flyway migratsiya qiladi, Hibernate `validate` qiladi. Entity kutgan, lekin
  migratsiya qo'shmagan ustun faqat shu yerda va prodda chiqadi.

```bash
./mvnw test -Dtest='MigrationChainTest,SchemaMatchesEntitiesTest'
```

**Bazani qayerdan oladi.** Docker demoni bo'lsa — Testcontainers, aynan
`docker-compose.yml` dagi `postgres:16-alpine` image'i bilan. Bo'lmasa —
`io.zonky.test:embedded-postgres`: o'sha major versiyadagi haqiqiy PostgreSQL
oddiy Maven artefakti sifatida keladi va oddiy jarayon bo'lib ishga tushadi.
Demon ham, root ham, o'rnatish ham kerak emas. Ikkalasi ham topilmasa test
**skip bo'lmaydi — yiqiladi**, sababini aytib.

Bu ataylab shunday. Ilgari bu testlar `disabledWithoutDocker = true` bilan
turardi va Docker'siz mashinada jimgina skip bo'lardi — yashil natijalar
ro'yxatida bu o'tgandek ko'rinadi. Natijada `MigrationChainTest` dagi
`flyway_schema_history` tekshiruvi noto'g'ri yozilgani (Flyway sxemani o'zi
yaratganda `type=SCHEMA` qatorini qo'shishi hisobga olinmagan edi) uzoq vaqt
sezilmay qoldi: test yozilgan, lekin hech qachon chopilmagan edi.
