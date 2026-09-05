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
Credentials ichida **ikkita** OAuth client kerak (iOS ham quriladigan bo'lsa —
uchta):

1. **Web application** — nomi chalg'itadi: bu vebsayt emas, "serverda ishlaydigan
   client" degani, ya'ni backendning o'zi. ID **allaqachon kodda**
   ([lib/api/api_config.dart](lib/api/api_config.dart)) — client ID maxfiy emas,
   u har bir build ichida ketadi. Serverga ham o'shanini bering:
   `GOOGLE_WEB_CLIENT_ID`. Aynan shu ID `idToken` ning `aud` iga yoziladi,
   server esa shuni tekshiradi. Boshqa Google loyihasiga o'tish kerak bo'lsa —
   `--dart-define=WB_GOOGLE_CLIENT_ID=...` kodni bosib o'tadi.
2. **Android** — package `com.wordbattle.word_battle`, va SHA-1 barmoq izlari:
   debug keystore, release keystore hamda Play App Signing (Play Console →
   Setup → App signing). Bu client kodda ishlatilmaydi, lekin usiz Google
   oynasi ochilmaydi.
3. **iOS** — faqat iOS build uchun. Bundle ID `com.wordbattle.wordBattle`,
   va Android'dan farqli o'laroq bu client ID kodda ishlatiladi — pastga qarang.

Web client ID kodda turgani uchun onboarding'da **Google tugmasi** ko'rinadi.
Dev login tugmasi faqat ID `TODO` bo'lganda paydo bo'ladi — ya'ni hozir yo'q.

⚠️ **Test users.** Yangi OAuth client "Testing" holatida bo'ladi va faqat
Cloud Console → **Audience → Test users** ro'yxatidagi akkauntlar kira oladi;
qolganlari `access_denied` oladi. Hammaga ochish uchun **Audience → Publish
app** — ilova faqat `openid`/`email`/`profile` so'ragani uchun Google
tekshiruvi (verification) talab qilinmaydi.

#### iOS

iOS client ID `--dart-define` bilan berilmaydi — u
[`ios/Runner/Info.plist`](ios/Runner/Info.plist) ichida yashaydi. Faylda uchta
`TODO-PASTE` joyi bor, hammasi izoh bilan belgilangan:

| `Info.plist` kaliti | Qiymat |
|---|---|
| `GIDClientID` | **iOS** client ID |
| `GIDServerClientID` | **Web** client ID — `ApiConfig.googleServerClientId` bilan aynan bir xil |
| `CFBundleURLTypes` → `CFBundleURLSchemes` | iOS client ID ning teskarisi (reversed) |

Reversed scheme — bu iOS client ID ning ikki bo'lagi joyini almashtirgani:

```
GIDClientID:  123456789012-abcdefgh.apps.googleusercontent.com
URL scheme:   com.googleusercontent.apps.123456789012-abcdefgh
```

Cloud Console'da iOS client sahifasida u tayyor holda **"iOS URL scheme"** deb
turadi — qo'lda yasagandan ko'ra shuni ko'chirgan ishonchli. Google kirish
natijasini aynan shu scheme orqali ilovaga qaytaradi.

Qadamlar:

1. Cloud Console → Credentials → Create credentials → OAuth client ID → **iOS**,
   Bundle ID: **`com.wordbattle.wordBattle`**. E'tibor bering, bu Android
   package (`com.wordbattle.word_battle`) bilan bir xil **emas** — iOS'da
   camelCase, Android'da pastki chiziq. Client aynan shu satr bo'yicha
   ro'yxatdan o'tadi, bir harf farq qilsa kirish ishlamaydi.
2. `Info.plist` dagi uchta joyni to'ldiring:
   `grep -n TODO-PASTE ios/Runner/Info.plist`.
3. `flutter build ipa` (macOS + Xcode kerak). `Podfile` repoda yo'q — birinchi
   build'da Flutter uni o'zi yaratadi. Minimal iOS **13.0**: loyiha ham
   (`IPHONEOS_DEPLOYMENT_TARGET`), plagin ham shuni so'raydi, ya'ni tegish shart
   emas.

**`GIDServerClientID` ni tashlab ketmang.** Usiz ham Google oynasi ochiladi va
kirish qurilmada muvaffaqiyatli tugaydi, lekin token iOS client nomiga
yoziladi va server uni rad etadi. Ilova `serverClientId` ni Dart tomondan ham
uzatadi, biroq iOS plagini uni faqat client ID bilan birga qabul qiladi —
shuning uchun iOS'da yagona manba shu `Info.plist`.

Shu sababdan **Dev login** tugmasi iOS'da ishonchli belgi emas: u faqat Web
client ID ga qarab yo'qoladi, `Info.plist` hali `TODO` bo'lsa ham. iOS'da
ikkalasini birga to'ldiring.

App Store'ga chiqarishdan oldin yana bittasi: Apple qoidalari uchinchi tomon
kirishini taklif qiladigan ilovadan **Sign in with Apple** ni ham talab qiladi.
Hozir ilovada u yo'q, ya'ni review shu sababdan qaytishi mumkin.

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
| Raqib qidirish | `queue.join` → `match.found` (35 s dan keyin bot) |
| Jang | `duel.update` freymlari; taymer ikki freym orasida lokal sanaydi |
| G'alaba / Mag'lubiyat | `duel.finished`: delta, reyting, o'rtacha vaqt, yangi so'zlar, maslahatlar |
| Reyting taxtasi | `GET /api/leaderboard/global` va `/friends` |
| Profil | `GET /api/users/me/profile` — statistika, 30 kunlik grafik, nishonlar |
| Do'stlar | `GET /api/friends`, `/requests`, `GET /api/users/search`, `invite.send` |
| Mashq | `GET /api/practice/word`, `/hints` |
| Turnir taklifi | `tournament.invite` freymi; javob — `tournament.accept`/`tournament.decline` |
| Turnir bracketi | `GET /api/tournaments/{id}` — istalgan tizimga kirgan foydalanuvchi uchun ochiq, faqat qatnashchilar uchun emas |
| Turnirni ulashish | Native share sheet orqali `https://wordbattle.example.uz/t/{id}` — Android ilovani to'g'ridan-to'g'ri bracketga ochadi, iOS'da havola brauzerda ochiladi |

**Ulanish uzilsa** soket o'zi qayta ulanadi (1→15 s backoff; birinchi freym
kelishi bilan hisob nolga qaytadi, shunda ikkinchi uzilish ham 1 soniyadan
boshlanadi va serverning 10 soniyalik muhlatiga ulguradi). Server jangning joriy
holatini qaytadan yuboradi. Ekran pastida qizil chiziq holatni aytadi.

**Token eskirsa** (401) yoki akkaunt o'chirilgan bo'lsa (`user_not_found`)
sessiya tozalanadi, Google akkaunti unutiladi va onboarding ochiladi. Soket
handshake'i 401 ni ayta olmagani uchun ikki marta uzilishdan keyin token REST
orqali tekshiriladi.

**Serverga umuman yetib bo'lmasa** token joyida qoladi va oflayn ekrani
"Qayta urinish" bilan ochiladi. Faqat serverning rad javobi tokenni o'chiradi:
tarmoq yo'qligi u haqida hech narsa aytmaydi. Ikkalasi bir xil ko'rilgan
paytda internetsiz ochilgan ilova odamni jimgina tizimdan chiqarib yuborardi.

**"Chiqish" serverga ham boradi.** Ilova `POST /api/auth/logout` ni chaqiradi va
server o'sha akkauntning barcha tokenlarini bekor qiladi — shundan keyin eski
token na REST'ga, na soketga kiritadi. Avval bu faqat qurilmadagi tokenni
o'chirardi: nusxasi bo'lgan odam (eski zaxira nusxa, proxy log, qo'ldan-qo'lga
o'tgan telefon) akkauntdan yana bir oy foydalana olardi. So'rov muvaffaqiyatsiz
bo'lsa ham (internet yo'q, server o'chgan) ilova baribir chiqadi — chiqishni
tarmoq to'sib qo'ymasligi kerak, faqat o'sha token bir oz uzoqroq yashaydi.

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
flutter test                 # 170 ta test
flutter analyze

cd backend && ./mvnw test    # 148 ta test
```

Ikkala to'plam ham hech narsa o'rnatishni talab qilmaydi va hech biri o'zini
skip qilmaydi.

- `test/layout_test.dart` — har bir ekran 360×784dp telefonda va klaviatura
  ochiq holatda toshib ketmasligi
- `test/screenshot_test.dart` — har ekranni `build/screens/*.png` ga render
  qiladi (ko'z bilan solishtirish uchun)
- `test/nav_transition_test.dart` — pastki panel animatsiyasi
- `test/api_client_test.dart` — server xatolari (401, `user_not_found`, tarmoq)
  ilova tushunadigan shaklga o'girilishi; tokenning URL'ga tushmasligi
- `test/session_test.dart` — saqlangan token qachon unutilishi. Serverning rad
  javobi (401, `user_not_found`) — ha; tarmoq yo'qligi yoki server xatosi —
  yo'q. Ilgari ikkalasi bir xil edi, shuning uchun internetsiz ochilgan ilova
  odamni butunlay tizimdan chiqarib yuborardi
- `test/queue_lifecycle_test.dart` — ilova fonga ketganda navbatdan chiqish va,
  eng muhimi, qaytganda unga qayta kirish
- backend: Glicko-2, taxallus qoidalari, Google `idToken` tekshiruvi, JWT sir
  talabi, duel qoidalari, REST oqimi va ikkita haqiqiy mijoz bilan WebSocket
  jangi (juftlanish, qayta ulanish, chaqiruv, ikki jang bo'lmasligi); Flyway
  migratsiyalari haqiqiy PostgreSQL'da — [`backend/README.md`](backend/README.md#migratsiya-testlari)

---

## Litsenziya

Kod — MIT ([LICENSE](LICENSE)). Ilova ichidagi shriftlar va so'z ro'yxatlari
o'z litsenziyalari ostida: [THIRD_PARTY.md](THIRD_PARTY.md).

---

## Hali yo'q

- **Google kirish qurilmada sinalmagan.** Web client ID kodda, Android client
  ro'yxatdan o'tgan, server tokenni tekshirishni biladi va u test bilan
  qoplangan — lekin hech kim haqiqiy Google akkaunti bilan kirib ko'rmagan.
  Birinchi sinovdan oldin: Cloud Console → Audience → **Test users** ga o'z
  akkauntingizni qo'shing (yuqoriga qarang).
- **iOS'da Google Sign-In** — `Info.plist` kalitlari joyida, lekin ichida uchta
  `TODO-PASTE` turibdi va hech kim uni macOS'da qurib ko'rmagan. Kerak: Cloud
  Console'dan iOS client (bundle `com.wordbattle.wordBattle`) va Sign in with
  Apple — README → "3. Google Sign-In" → "iOS".
- **Push (FCM)** — oflayn do'stga chaqiruv bormaydi.
- **Bitta qurilmadan chiqish — hammasidan chiqish.** Token bekor qilish akkaunt
  bo'yicha hisoblagichga bog'langan (`users.token_generation`), tokenning
  o'ziga emas. Ya'ni telefonda "Chiqish" bosilsa, planshetdagi seans ham
  o'ladi. Bitta telefonda o'ynaladigan o'yin uchun bu xavfsizroq tomon, lekin
  agar har bir qurilmani alohida chiqarish kerak bo'lsa — har bir kirish uchun
  saqlanadigan qator (`jti`) kerak bo'ladi.
- Bitta server instansiyasi uchun mo'ljallangan (navbat va onlayn holat
  xotirada). Ko'p nusxa kerak bo'lsa — Redis. Server o'chganda faol janglar
  `duel.aborted` bilan yopiladi, lekin qayta tiklanmaydi.
