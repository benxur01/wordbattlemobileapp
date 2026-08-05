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

Release APK:

```bash
flutter build apk --release --dart-define=WB_API=https://api.example.com
```

---

## Ilova qanday ishlaydi

Ilovada o'yin mantiqi **yo'q**. Kim yutgani, so'z to'g'rimi, navbat kimda,
taymer qancha qoldi — hammasini server hal qiladi. Ilova faqat serverdan
kelganini chizadi va o'yinchining harakatini qaytarib yuboradi. O'zgartirilgan
APK istalgan narsani yubora oladi — natija rad javobi bo'ladi.

| Ekran | Manba |
|---|---|
| Onboarding 1 | `POST /api/auth/telegram` (yoki dev login) |
| Onboarding 2 | `GET /api/users/nickname/check` (har 400 ms), `PUT /api/users/me/nickname` |
| Lobbi | `hello` freym: profil, onlayn soni; `GET /api/friends` |
| Raqib qidirish | `queue.join` → `match.found` (12 s dan keyin bot) |
| Jang | `duel.update` freymlari; taymer ikki freym orasida lokal sanaydi |
| G'alaba / Mag'lubiyat | `duel.finished`: delta, reyting, o'rtacha vaqt, yangi so'zlar, maslahatlar |
| Reyting taxtasi | `GET /api/leaderboard/global` va `/friends` |
| Profil | `GET /api/users/me/profile` — statistika, 30 kunlik grafik, nishonlar |
| Do'stlar | `GET /api/friends`, `/requests`, `GET /api/users/search`, `invite.send` |
| Mashq | `GET /api/practice/word`, `/hints` |

**Ulanish uzilsa** soket o'zi qayta ulanadi (1→15 s backoff), server esa jangning
joriy holatini qaytadan yuboradi. Ekran pastida qizil chiziq holatni aytadi.

**Token eskirsa** (401) sessiya tozalanadi va onboarding ochiladi.

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
flutter test                 # 51 ta test
flutter analyze

cd backend && ./mvnw test    # 29 ta test
```

- `test/layout_test.dart` — har bir ekran 360×784dp telefonda va klaviatura
  ochiq holatda toshib ketmasligi
- `test/screenshot_test.dart` — har ekranni `build/screens/*.png` ga render
  qiladi (ko'z bilan solishtirish uchun)
- `test/nav_transition_test.dart` — pastki panel animatsiyasi
- backend: Glicko-2, taxallus qoidalari, Telegram imzosi, duel qoidalari,
  REST oqimi va ikkita haqiqiy mijoz bilan WebSocket jangi

---

## Litsenziya

Kod — MIT ([LICENSE](LICENSE)). Ilova ichidagi shriftlar va so'z ro'yxatlari
o'z litsenziyalari ostida: [THIRD_PARTY.md](THIRD_PARTY.md).

---

## Hali yo'q

- **Telegram login** — server tayyor, ilova hozircha dev login ishlatadi
  (`AppRoot.login()`). Telegram Mini App `initData` sini olish qismi kerak.
- **Push (FCM)** — oflayn do'stga chaqiruv bormaydi.
- **Rate limiting** va **token bekor qilish** (batafsil `backend/README.md` da).
- Bitta server instansiyasi uchun mo'ljallangan (navbat va onlayn holat
  xotirada). Ko'p nusxa kerak bo'lsa — Redis.
