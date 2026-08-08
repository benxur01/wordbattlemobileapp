# Word Battle

1v1 ingliz so'z zanjiri o'yini. Flutter ilovasi + Java Spring Boot server.

```
lib/          Flutter ilovasi (UI Claude Design maketidan ko'chirilgan)
lib/api/      REST klient, WebSocket, model'lar, sessiya
backend/      Spring Boot server — barcha o'yin qoidalari shu yerda
test/         layout, screenshot va navigatsiya testlari
```

---

## Ishga tushirish

### 1. Server

```bash
cd backend
cp .env.example .env        # JWT_SECRET ni to'ldiring: openssl rand -base64 48
docker compose up --build
```

To'liq ma'lumot (API, WebSocket protokoli, sozlamalar): [`backend/README.md`](backend/README.md).

### 2. Ilova

Server manzili build vaqtida beriladi:

```bash
# Telefon USB orqali ulangan, server kompyuterda:
adb reverse tcp:8080 tcp:8080
flutter run --dart-define=WB_API=http://localhost:8080

# Yoki bir tarmoqdagi server:
flutter run --dart-define=WB_API=http://192.168.1.10:8080
```

`WB_API` berilmasa `http://localhost:8080` ishlatiladi.

Release build'da manzil **https** bo'lishi shart: shipped APK cleartext HTTP'ni
rad etadi (`usesCleartextTraffic="false"`). Debug build'da esa `http://` ishlaydi
— `android/app/src/debug/` dagi network security config shuning uchun bor.

```bash
flutter build appbundle --release --dart-define=WB_API=https://api.example.com
```

### Release imzosi

Play debug kalit bilan imzolangan paketni qabul qilmaydi, Google Sign-In esa
sertifikat SHA-1 iga bog'langan. Bir marta upload keystore yarating va
`android/key.properties` ni to'ldiring:

```bash
cp android/key.properties.example android/key.properties   # keyin to'ldiring
keytool -genkey -v -keystore ~/wordbattle-upload.jks \
        -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

`key.properties` bo'lmasa `flutter build appbundle` **ataylab yiqiladi** va nima
qilish kerakligini aytadi. Sababi: debug kalit bilan imzolangan `.aab` tashqi
tomondan tayyor ko'rinadi, lekin Play uni qabul qilmaydi va Google Sign-In ham
ishlamaydi — buni yuklash paytida bilib qolgandan ko'ra, build paytida bilgan
yaxshi. Lokal sinov uchun `flutter build apk --release` ishlayveradi (u debug
kalit bilan imzolanadi).

### 3. Google Sign-In

Kirish faqat Google orqali. Google Cloud Console → APIs & Services →
Credentials ichida **ikkita** OAuth client kerak:

1. **Web application** — uning ID sini ikki joyga qo'ying:
   `ApiConfig.googleServerClientId` ([lib/api/api_config.dart](lib/api/api_config.dart), hozir `TODO` turibdi)
   va serverda `GOOGLE_WEB_CLIENT_ID`. Aynan shu ID `idToken` ning `aud` iga
   yoziladi, server esa shuni tekshiradi.
2. **Android** — package `com.wordbattle.word_battle`, va SHA-1 barmoq izlari:
   debug keystore, release keystore hamda Play App Signing (Play Console →
   Setup → App signing). Bu client kodda ishlatilmaydi, lekin usiz Google
   oynasi ochilmaydi.

ID qo'yilmaguncha onboarding ekranida kichik **Dev login** tugmasi turadi
(server `DEV_LOGIN_ENABLED=true` bilan ishlashi kerak); haqiqiy ID qo'yilgach
u o'zi yo'qoladi.

---

## Ilova qanday ishlaydi

Ilovada o'yin mantiqi **yo'q**. Kim yutgani, so'z to'g'rimi, navbat kimda,
taymer qancha qoldi — hammasini server hal qiladi. Ilova faqat serverdan
kelganini chizadi va o'yinchining harakatini qaytarib yuboradi. O'zgartirilgan
APK istalgan narsani yubora oladi — natija rad javobi bo'ladi.

| Ekran | Manba |
|---|---|
| Onboarding 1 | `POST /api/auth/google` (yoki dev login) |
| Onboarding 2 | `GET /api/users/nickname/check` (har 400 ms), `PUT /api/users/me/nickname` |
| Lobbi | `hello` freym: profil, onlayn soni; `GET /api/friends` |
| Raqib qidirish | `queue.join` → `match.found` (12 s dan keyin bot) |
| Jang | `duel.update` freymlari; taymer ikki freym orasida lokal sanaydi |
| G'alaba / Mag'lubiyat | `duel.finished`: delta, reyting, o'rtacha vaqt, yangi so'zlar, maslahatlar |
| Reyting taxtasi | `GET /api/leaderboard/global` va `/friends` |
| Profil | `GET /api/users/me/profile` — statistika, 30 kunlik grafik, nishonlar |
| Do'stlar | `GET /api/friends`, `/requests`, `GET /api/users/search`, `invite.send` |
| Mashq | `GET /api/practice/word`, `/hints` |

**Ulanish uzilsa** soket o'zi qayta ulanadi (1→15 s backoff; birinchi freym
kelishi bilan hisob nolga qaytadi, shunda ikkinchi uzilish ham 1 soniyadan
boshlanadi va serverning 10 soniyalik muhlatiga ulguradi). Server jangning joriy
holatini qaytadan yuboradi. Ekran pastida qizil chiziq holatni aytadi.

**Token eskirsa** (401) yoki akkaunt o'chirilgan bo'lsa (`user_not_found`)
sessiya tozalanadi, Google akkaunti unutiladi va onboarding ochiladi. Soket
handshake'i 401 ni ayta olmagani uchun ikki marta uzilishdan keyin token REST
orqali tekshiriladi.

**Profil ekranida** "Chiqish" va "Akkauntni o'chirish" bor. O'chirish qaytmaydi:
do'stlar, so'rovlar, reyting tarixi va o'rganilgan so'zlar o'chadi, `users`
qatori esa nomsiz qobiq bo'lib qoladi — raqiblaringizning jang tarixi shunga
bog'langan va uni o'chirish ularning yozuvini ham yo'q qilardi.

---

## Dizayndan farqlar

Maket statik prototip edi; jonli ma'lumot bilan ba'zi joylar boshqacha:

- **Yuklanish va oflayn ekranlari** qo'shildi — maketda ular yo'q edi.
- **Bot janglari reytingsiz** (`rated: false`). G'alaba ekranida delta o'rniga
  "Mashq jangi · reyting o'zgarmadi" yoziladi. Aks holda ladderni bot ustidan
  yig'ish oson bo'lardi.
- **Raqibning navbatida** input o'chiriladi va "raqib o'ylayapti…" ko'rinadi.
- **Bo'sh holatlar**: do'st yo'q, hech kim onlayn emas, grafik uchun ma'lumot
  kam — maketda hammasi to'ldirilgan holda chizilgan edi.
- **Avatar ranglari** foydalanuvchi id'sidan olinadi, shunda bir odam hamma
  ekranda bir xil rangda ko'rinadi (maketda har qator qo'lda bo'yalgan edi).
- **Mashq ekrani inputi** ishlamaydi — maketda ham ishlamagan, serverda ham
  mashq jangi hali yo'q. So'zni yutib yuboradigan maydondan ko'ra yo'qligi
  yaxshiroq.

---

## Testlar

```bash
flutter test                 # 60 ta test
flutter analyze

cd backend && ./mvnw test    # 44 ta test
```

- `test/layout_test.dart` — har bir ekran 360×784dp telefonda va klaviatura
  ochiq holatda toshib ketmasligi
- `test/screenshot_test.dart` — har ekranni `build/screens/*.png` ga render
  qiladi (ko'z bilan solishtirish uchun)
- `test/nav_transition_test.dart` — pastki panel animatsiyasi
- `test/api_client_test.dart` — server xatolari (401, `user_not_found`, tarmoq)
  ilova tushunadigan shaklga o'girilishi; tokenning URL'ga tushmasligi
- backend: Glicko-2, taxallus qoidalari, Google `idToken` tekshiruvi, JWT sir
  talabi, duel qoidalari, REST oqimi va ikkita haqiqiy mijoz bilan WebSocket
  jangi (juftlanish, qayta ulanish, chaqiruv, ikki jang bo'lmasligi)

---

## Litsenziya

Kod — MIT ([LICENSE](LICENSE)). Ilova ichidagi shriftlar va so'z ro'yxatlari
o'z litsenziyalari ostida: [THIRD_PARTY.md](THIRD_PARTY.md).

---

## Hali yo'q

- **Google Web client ID** — `ApiConfig.googleServerClientId` hali `TODO`.
  Uni qo'ymaguncha ilovaga faqat dev login bilan kiriladi, prodda esa (dev login
  o'chiq) kirishning yo'li yo'q. Yagona qadam sizdan: Cloud Console'dagi qiymat.
- **Jang tarixi ekrani** — `GET /api/matches` va `ApiClient.matchHistory()`
  tayyor, ularni ko'rsatadigan ekran hali chizilmagan.
- **iOS'da Google Sign-In** — Android tayyor; iOS uchun `Info.plist` ga iOS
  client ID va uning reversed URL scheme'i qo'shilishi kerak.
- **Push (FCM)** — oflayn do'stga chaqiruv bormaydi.
- **Token bekor qilish (revocation)** — chiqish qurilmadagi tokenni o'chiradi,
  lekin server tomonda u muddati tugagunicha yaroqli qoladi.
- **Migratsiyalarni test qilish** — testlar H2 da `ddl-auto: create-drop` bilan
  ishlaydi, Flyway migratsiyalari esa faqat prodda birinchi marta bajariladi.
  To'g'ri yechim — Testcontainers Postgres (Docker talab qiladi).
- Bitta server instansiyasi uchun mo'ljallangan (navbat va onlayn holat
  xotirada). Ko'p nusxa kerak bo'lsa — Redis. Server o'chganda faol janglar
  `duel.aborted` bilan yopiladi, lekin qayta tiklanmaydi.
