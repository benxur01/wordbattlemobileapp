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

Testlar (Postgres kerak emas — H2 da ishlaydi):

```bash
./mvnw test
```

Migratsiya testlari haqiqiy PostgreSQL so'raydi va Docker bo'lmasa o'zini
o'zi skip qiladi — pastdagi [Testlar](#testlar) bo'limiga qarang.

---

## Konfiguratsiya

| Env | Nima uchun | Standart |
|---|---|---|
| `DB_URL`, `DB_USER`, `DB_PASSWORD` | PostgreSQL ulanishi | `localhost:5432/wordbattle` |
| `JWT_SECRET` | Tokenlarni imzolash. **Kamida 32 bayt. Standart qiymat yo'q** — berilmasa server ko'tarilmaydi | — |
| `CORS_ALLOWED_ORIGINS` | Brauzer origin'lari (vergul bilan). Bo'sh bo'lsa CORS umuman yo'q — telefon ilovasiga kerak emas | bo'sh |
| `TIME_ZONE` | Streak va kunlik so'z qaysi kun bo'yicha almashadi | `Asia/Tashkent` |
| `WS_FRAMES_PER_SECOND` / `WS_FRAME_BURST` | Soketdagi freym cheklovi (bitta o'yinchiga) | `20` / `40` |
| `JWT_TTL` | Token amal qilish muddati (ISO-8601) | `P30D` |
| `GOOGLE_WEB_CLIENT_ID` | Google **Web** OAuth client ID; bo'sh bo'lsa Google login o'chadi | bo'sh |
| `DEV_LOGIN_ENABLED` | `/api/auth/dev` ni yoqadi — **prodda hech qachon** | `false` |
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

---

## REST API

Barchasi `/api` ostida. `*` — token talab qilinmaydi.

### Auth
| Method | Path | Izoh |
|---|---|---|
| POST\* | `/auth/google` | `{idToken}` → `{token, user, needsNickname}` |
| POST\* | `/auth/dev` | `{displayName}` — faqat `DEV_LOGIN_ENABLED=true` |

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
| `duel.submit` | `{word}` | so'z yuboradi |
| `duel.forfeit` | — | jangdan chiqadi (mag'lubiyat) |
| `invite.send` | `{userId}` | do'stni jangga chaqiradi |
| `invite.accept` / `invite.decline` | `{inviteId}` | chaqiruvga javob |
| `ping` | — | `pong` qaytadi |

### Server → mijoz

| type | Muhim maydonlar |
|---|---|
| `hello` | `user`, `rules{turnSeconds,minWordLength,wordsToWin,inviteTimeoutSeconds}`, `onlineCount`, `pendingFriendRequests` |
| `queue.joined` / `queue.left` | — |
| `match.found` | `duelId, opponent, rated, yourTurn, seedWord, needLetter, turnSeconds, chain[]` |
| `duel.update` | `chain[{word,mine,spentMs}], yourTurn, needLetter, timeLeftMs, yourWords, opponentWords, opponentThinking` |
| `duel.rejected` | `code, message` — **navbat yo'qolmaydi**, faqat xato ko'rsatiladi |
| `duel.finished` | `result(win/lose), reason, rated, delta, ratingBefore, ratingAfter, chainLength, yourWords, averageMs, newWords, streakDays, stuckLetter, hints[]` |
| `invite.sent` / `invite.incoming` / `invite.declined` / `invite.expired` | `inviteId`, `from`/`to`, `expiresInSeconds` |
| `duel.aborted` | `duelId, message` — server o'chmoqda, jang hech kimning foydasiga tugamadi |
| `error` | `code, message` |

`duel.rejected` kodlari: `letters_only`, `too_short`, `wrong_letter`,
`already_used`, `not_a_word`, `not_your_turn`.

Uzilish = mag'lubiyat: soket yopilsa server jangni raqib foydasiga tugatadi
(aks holda simni sug'urish bepul qochish yo'li bo'lardi). Qayta ulanganda
server jangning joriy holatini o'zi yuboradi.

---

## Qanday ishlaydi

**Raqib qidirish.** Navbatdagi o'yinchi ±75 reyting oynasi bilan boshlaydi,
oyna har 3 soniyada 25 ga kengayadi (maksimum ±400). 12 soniyada odam
topilmasa — bot bilan jang boshlanadi.

**Bot janglari reytingsiz.** Ular kutish ekranida qotib qolmaslik uchun bor;
reyting bersa, ladderni bot ustidan yig'ish juda oson bo'lardi. Streak,
statistika va o'rganilgan so'zlar esa hisobga olinadi (`rated: false`).

**So'z tekshiruvi.** ~357 700 so'zli ro'yxat serverda (`words/valid-en.txt`),
bot esa ~7 350 keng tarqalgan so'zdan tanlaydi, shunda uning yurishlari tabiiy
ko'rinadi. Ikkala ro'yxat ham yuklanish paytida filtrlanadi — qisqartmalar
hammadan, atoqli otlar esa bot pulidan olib tashlanadi (`THIRD_PARTY.md`).

**Reyting.** Glicko-2 (rating / deviation / volatility), har jang — bitta
davr. Yangi o'yinchi tez, tajribalisi sekin harakatlanadi.

**"Yangi so'z" hisobi.** `user_words` jadvali har bir o'yinchi o'ynagan
so'zlarni eslab qoladi, shuning uchun g'alaba ekranidagi son haqiqiy.

---

## Ma'lumotlar bazasi

Flyway migratsiyalari `src/main/resources/db/migration`:

- `users` — profil, Glicko-2 ko'rsatkichlari, statistika, streak
- `friendships` (har yo'nalish uchun bitta qator), `friend_requests`
- `matches`, `match_words` — jang tarixi va zanjir
- `rating_history` — profil grafigi uchun
- `practice_words`, `user_words`

Taxalluslar registrga bog'liq bo'lmagan holda unikal: `lower(nickname)`
ustidagi unikal indeks. Ikki o'yinchi bir vaqtda bir nomni so'rasa, biri
`409` oladi.

---

## Prodga chiqarishdan oldin

1. `JWT_SECRET` va `GOOGLE_WEB_CLIENT_ID` ni to'ldiring, `DEV_LOGIN_ENABLED=false`.
   (Sirsiz server ataylab ko'tarilmaydi.)
2. HTTPS/WSS terminatsiyasi (nginx yoki cloud LB) qo'ying — ilova release
   build'da cleartext HTTP'ni umuman rad etadi.
3. Postgres uchun zaxira nusxa (backup) sozlang.
4. `/actuator/health/readiness` va `/liveness` ni monitoringga ulang.

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

### Migratsiya testlari (Docker kerak)

Yuqoridagilarning hammasi H2 da `ddl-auto: create-drop` bilan ishlaydi: sxemani
entity'lardan Hibernate quradi, `db/migration` fayllari esa umuman ochilmaydi.
Prodda teskarisi — sxemani Flyway quradi, Hibernate faqat `validate` qiladi.
Ya'ni H2 suite'i migratsiyalar haqida hech narsa isbotlamaydi, ular esa
birinchi marta prodda ishga tushadi va yiqilsa server umuman ko'tarilmaydi.

Shu bo'shliqni ikkita test yopadi. Ikkalasi Testcontainers orqali bitta
`postgres:16-alpine` (docker-compose'dagi image) ko'taradi va uni bo'lishadi:

- `MigrationChainTest` — bo'sh sxemada V1→V5 zanjiri to'liq bajarilishi
  (`baseline-on-migrate: true` V1 ni tashlab ketmasligi ham shu yerda),
  qisman indekslar predikati bilan saqlanishi, qayta `migrate` bo'sh amal
  bo'lishi. Ikkinchi test — **mavjud bazani yangilash**: V2 da ma'lumot
  solinadi, so'ng V3 ustunni tashlaydi va V5 to'la jadvalga `not null` ustun
  qo'shadi. Noldan yaratish bu yo'lni umuman tekshirmaydi.
- `SchemaMatchesEntitiesTest` — server aynan proddagi juftlik bilan ko'tariladi:
  Flyway migratsiya qiladi, Hibernate `validate` qiladi. Entity kutgan, lekin
  migratsiya qo'shmagan ustun faqat shu yerda va prodda chiqadi.

```bash
# Docker demoni ishlab turishi shart
./mvnw test -Dtest='MigrationChainTest,SchemaMatchesEntitiesTest'
```

Docker yo'q bo'lsa ikkalasi ham **skip** bo'ladi (`disabledWithoutDocker is true
and Docker is not available`) — `./mvnw test` Docker'siz mashinada ham yashil
qoladi, faqat migratsiyalar tekshirilmagan holda o'tadi.
