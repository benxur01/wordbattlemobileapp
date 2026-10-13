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
# backend/.env faylida API_BIND_ADDRESS=0.0.0.0 qiling (faqat lokal development uchun)
flutter run --dart-define=WB_API=http://192.168.1.10:8080
```

`WB_API` berilmasa `http://localhost:8080` ishlatiladi — bu faqat debug build
uchun.

Release build'da manzil **https** bo'lishi shart: shipped APK cleartext HTTP'ni
rad etadi (`usesCleartextTraffic="false"`). Debug build'da esa `http://` ishlaydi
— `android/app/src/debug/` dagi network security config shuning uchun bor.

```bash
flutter build appbundle --release --dart-define=WB_API=https://<domain>
# Admin panel (web) ham xuddi shunday:
flutter build web -t lib/main_admin.dart --dart-define=WB_API=https://<domain>
```

`WB_API` siz yoki `http://` manzil bilan qurilgan release build serverga
umuman so'rov yubormaydi va har urinishda "Server manzili sozlanmagan
(WB_API). Ilova HTTPS serverga yo'naltirilmagan." xatosini ko'rsatadi
(`lib/api/rest_transport.dart`). Aks holda u "internetni tekshiring" deb
yiqilardi va asl sababni hech narsa ko'rsatmasdi.

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

### Domen olinganda

Haqiqiy domen hali yo'q: ulashiladigan turnir havolalari `wordbattle.example.uz`
o'rinbosariga qaraydi. Domen (masalan, `wordbattle.uz`) olinganda kodga tegish
shart emas — faqat quyidagilar beriladi:

| Qayerda | Nima | Misol |
|---|---|---|
| ilova build'i | `--dart-define=WB_API=https://<domen>` — server manzili (admin panel web build'i ham) | `https://wordbattle.uz` |
| ilova build'i | `--dart-define=WB_LINK_HOST=<domen>` — ulashiladigan havola `https://<domen>/t/<id>` shu domenga yoziladi | `wordbattle.uz` |
| Android build | `wbLinkHost=<domen>` — `android/gradle.properties` da yoki `ORG_GRADLE_PROJECT_wbLinkHost` env orqali. **`WB_LINK_HOST` bilan aynan bir xil** bo'lsin: biri havolani yozadi, ikkinchisi (manifestdagi App Links filtri) uni ilovada ochadi | `wordbattle.uz` |
| server `.env` | `ASSETLINKS_SHA256` — release imzo sertifikatining SHA-256 barmoq izi, bir nechtasi vergul bilan. Play App Signing bo'lsa Play Console → Setup → App signing dagi "App signing key certificate" | `14:6D:E9:…` |
| server `.env` | `CORS_ALLOWED_ORIGINS` — faqat admin panel (web) API'dan boshqa origin'da ochilsa | `https://admin.wordbattle.uz` |

```bash
flutter build appbundle --release \
  --dart-define=WB_API=https://wordbattle.uz \
  --dart-define=WB_LINK_HOST=wordbattle.uz
```

Android havolani ilovaga faqat `https://<WB_LINK_HOST>/.well-known/assetlinks.json`
(HTTPS orqali, redirektsiz) ilovaning imzosini ko'rsatsa beradi. Bu faylni
server `ASSETLINKS_SHA256` dan yig'adi, ya'ni `WB_LINK_HOST` shu serverga
qarashi kerak — eng soddasi `WB_API` bilan bitta domen.

### Maxfiylik siyosati va shartlar

Server ikkita ochiq sahifa beradi: `https://<domen>/privacy` va
`https://<domen>/terms`. Play Console va App Store Connect aynan shu
havolalarni so'raydi, ilovada esa ular Profil ekranida turadi. Matn
[`backend/src/main/resources/legal/`](backend/src/main/resources/legal/) da,
aloqa manzili va operator nomi server `.env` idan qo'yiladi:
`LEGAL_CONTACT_EMAIL`, `LEGAL_OPERATOR_NAME` (bermasangiz `support@example.uz`
va `Word Battle` o'rinbosarlari chiqadi).
Production profilida server ushbu o'rinbosar qiymatlar bilan ishga tushmaydi;
haqiqiy operator nomi va aloqa manzilini `.env` da kiriting.

⚠️ **Bu matn — shablon, yuridik maslahat emas.** U ilova haqiqatda
to'playdigan ma'lumotlar (kod va migratsiyalar) asosida yozilgan, lekin
do'konga chiqarishdan oldin uni yurist ko'rib chiqishi kerak. Ayniqsa:
operatorning to'liq yuridik nomi, bolalar uchun yosh chegarasi (hozir 13),
shikoyatlarni "odatda 24 soat ichida" ko'rib chiqish va'dasi (App Store 1.2
talabi — va'da qilingan ekan, bajarilishi kerak), amaldagi qonunchilik va
O'zbekistonning shaxsiy ma'lumotlar to'g'risidagi qonuni talablari (masalan,
fuqarolar ma'lumotlarini O'zbekiston hududidagi serverda saqlash).

### 3. Google Sign-In

Kirishning ikki yo'li bor: Google Sign-In va taxallus + parol (onboarding
ekranidagi «Ro'yxatdan o'tish» / «Kirish» — server tomonida
`POST /api/auth/register` va `/api/auth/login`). Parol yo'li Google'siz ham
ishlaydi; quyidagilar faqat Google tugmasi uchun kerak.

Google Cloud Console → APIs & Services → Credentials ichida Android va Web
uchun **ikkita** OAuth client kerak. iOS Google login hozircha o'chirilgan;
Apple Sign-In'dan keyin uni ham qo'shsangiz iOS client uchinchi bo'ladi:

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
3. **iOS** — faqat keyin iOS Google login integratsiyasi qo'shilsa kerak bo'ladi.
   Bundle ID `com.wordbattle.wordBattle`; tafsilotlar pastda.

Web client ID kodda turgani uchun onboarding'da **Google tugmasi** ko'rinadi.
Dev login tugmasi Google client ID bo'sh yoki `TODO` bo'lganda paydo bo'ladi.

⚠️ **Test users.** Yangi OAuth client "Testing" holatida bo'ladi va faqat
Cloud Console → **Audience → Test users** ro'yxatidagi akkauntlar kira oladi;
qolganlari `access_denied` oladi. Hammaga ochish uchun **Audience → Publish
app** — ilova faqat `openid`/`email`/`profile` so'ragani uchun Google
tekshiruvi (verification) talab qilinmaydi.

#### iOS

iOS build'da Google kirishi hozircha ataylab o'chirilgan: iOS'da uchinchi tomon
kirishini taklif qilishdan oldin Apple bilan kirish ham qo'shilishi kerak.
Taxallus va parol orqali kirish ishlaydi. Apple Sign-In integratsiyasi va App
Store sozlamalari bajarilmaguncha iOS Google OAuth client ID'sini yoki URL
scheme'ni kiritmang.

Apple Sign-In qo'shilgandan keyin Google'ni ham iOS'da yoqmoqchi bo'lsangiz,
alohida iOS OAuth client va ilova kodida iOS `clientId` ni plugin'ga uzatish
qo'shilishi kerak. Hozir bu kod yo'q; pastdagi qadamlar faqat shu integratsiya
qo'shilgandan keyin qo'llanadi. Callback URL scheme
[`ios/Runner/Info.plist`](ios/Runner/Info.plist) ichida ro'yxatdan o'tishi kerak.

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
2. `Info.plist` dagi `GIDClientID` va URL scheme qiymatlarini to'ldiring.
   `GIDServerClientID` Web client ID bilan aynan bir xil qolishi kerak.
3. Kod iOS client ID ni o'qib Google plugin'iga uzatadigan qilib yangilang;
   keyin build vaqtida uni bering:
   `flutter build ipa --dart-define=WB_GOOGLE_IOS_CLIENT_ID=<iOS-client-ID>`.
   `WB_API` ni ham HTTPS serverga yo'naltiring. `Podfile` repoda yo'q — birinchi
   build'da Flutter uni o'zi yaratadi. Minimal iOS **13.0**: loyiha ham
   (`IPHONEOS_DEPLOYMENT_TARGET`), plagin ham shuni so'raydi, ya'ni tegish shart
   emas.

**`GIDServerClientID` ni tashlab ketmang.** U Web client ID bilan mos
bo'lmasa, Google tokenini server rad etadi. iOS Google integratsiyasi
qo'shilganda ilova `clientId` va `serverClientId` ni Google plaginiga
uzatishi, iOS client ID va URL scheme esa bir-biriga mos bo'lishi shart.

Hozir iOS'da Google tugmasi yo'q, shuning uchun ilova taxallus/parol bilan
kiradi. iOS'da Google yoki boshqa uchinchi tomon kirishini yoqishdan oldin
**Sign in with Apple** integratsiyasi va Apple Developer capability'sini ham
qo'shish kerak.

---

## Ilova qanday ishlaydi

Ilovada o'yin mantiqi **yo'q**. Kim yutgani, so'z to'g'rimi, navbat kimda,
taymer qancha qoldi — hammasini server hal qiladi. Ilova faqat serverdan
kelganini chizadi va o'yinchining harakatini qaytarib yuboradi. O'zgartirilgan
APK istalgan narsani yubora oladi — natija rad javobi bo'ladi.

| Ekran | Manba |
|---|---|
| Onboarding 1 | Android/web: `POST /api/auth/google`; parol: `POST /api/auth/register` yoki `/api/auth/login`; dev: `POST /api/auth/dev` |
| Onboarding 2 | `GET /api/users/nickname/check` (har 400 ms), `PUT /api/users/me/nickname` |
| Lobbi | `hello` freym: profil, onlayn soni; `GET /api/friends` |
| Raqib qidirish | `queue.join` → `match.found` (35 s dan keyin bot, reytingingizdan +75) |
| Bot bilan jang | `GET /api/themes` (mavzular ro'yxati), `queue.bot` (tanlangan reyting, serverda 200–2000 oralig'iga qisiladi + ixtiyoriy mavzu) → `match.found`; jang davomida to'rtta kuchaytirgich (`duel.power_up`), har biri bir marta — reytingli janglarda ular yo'q |
| Jang | `duel.update` freymlari; taymer ikki freym orasida lokal sanaydi |
| G'alaba / Mag'lubiyat | `duel.finished`: delta, reyting, o'rtacha vaqt, yangi so'zlar, maslahatlar |
| Reyting taxtasi | `GET /api/leaderboard/global` va `/friends` |
| Profil | `GET /api/users/me/profile` — statistika, 30 kunlik grafik, nishonlar |
| Do'stlar | `GET /api/friends`, `/requests`, `GET /api/users/search`, `invite.send` |
| Mashq | `GET /api/practice/word`, `/hints` |
| Turnir taklifi | `tournament.invite` freymi; javob — `tournament.accept`/`tournament.decline` |
| Turnir bracketi | `GET /api/tournaments/{id}` — istalgan tizimga kirgan foydalanuvchi uchun ochiq, faqat qatnashchilar uchun emas |
| Turnirni ulashish | Native share sheet orqali `https://<WB_LINK_HOST>/t/{id}` — Android ilovani to'g'ridan-to'g'ri bracketga ochadi, iOS'da havola brauzerda ochiladi |

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
- **iOS release sozlamalari** — hozircha Google login o'chirilgan, taxallus va
  parol bilan kirish ishlaydi. Apple Developer capability hamda App Store
  sozlamalari hisob egasi tomonidan bajarilishi kerak; Apple login qo'shilgach
  iOS Google OAuth'ni yoqish ham mumkin.
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
