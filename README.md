# Family Finance 💰

A cross-platform **Flutter** app (Android, iOS & Web) to manage a household's
money — salary, expenses, EMIs, reminders, reports and a **shared family
"common wallet"** multiple people contribute to.

> ### 🌍 Going global (free) — read this first
> By default the app stores data as Excel files in **your own Google Drive**,
> which (because of Google's restricted-scope rules) only works for *allow-listed
> test users*. To make it work for **everyone, worldwide**, switch on the **free
> Firestore backend** — no credit card, no server, ~10-minute setup. See
> **[FIREBASE_SETUP.md](FIREBASE_SETUP.md)**. Once `lib/firebase_options.dart`
> holds real values the app auto-switches to Firestore; until then it keeps
> using Drive, so nothing breaks.
>
> With Firestore: sign in is the **basic Google profile scope** (no
> verification), you choose **Family Head** or **Member** at first login, and
> you invite people by sharing a **family code** via email/WhatsApp.

## Features

- 🔐 **Login** with Google Sign-In. Uses the Google **`drive`** scope so that
  an invited member can open the *one* shared family workbook the owner created
  — the shared "common wallet"/expenses can't sync across accounts under the
  narrower `drive.file` scope. (See the multi-user note below.)
- 👤 **My Details** — profile, currency, and family linking.
- 👥 **Users / Master page** — manage multiple users (multi-user roster),
  roles, and invitations; reference master data (expense categories).
- 💵 **Salary / Income** — record multiple income sources.
- 🧾 **Expenses** — categorised spending, payment mode, optionally paid from
  the family wallet.
- 🏦 **EMIs / Loans** — track tenure, paid vs **remaining EMIs**, remaining
  amount, next due date and payoff date; record monthly payments.
- 🔔 **Payment reminders** — recurring (or one-off) reminders for **EMIs,
  repayments, groceries, bills, recharges and other mandatory needs**. Each has
  a due date and cadence (weekly / monthly / quarterly / yearly); overdue and
  due-soon items surface on the Dashboard and behind a badged bell, and
  "mark paid" rolls a recurring reminder to its next date (optionally booking
  the matching expense). In-app alerts — works on Android, iOS and Web.
- 📊 **Reports** — **month-wise** and **year-wise** summaries, income-vs-expense
  charts, category pie chart, and **savings/spending targets** with
  planned-vs-actual progress.
- 👨‍👩‍👧 **Family common wallet** — a shared `.xlsx` on Drive; every member can
  top-up or spend, with a live balance and full history.
- 📁 **Excel storage on Drive** — open the files in Excel/Sheets any time.

### How data is stored on Drive

A `FamilyFinance` folder is created in your Drive containing:

| File                         | Sheets                                                   |
|------------------------------|----------------------------------------------------------|
| `personal_<email>.xlsx`      | Profile, Salary, Expenses, EMIs, Targets, Reminders, Activity |
| `family_<familyId>.xlsx`     | Members, Wallet, FamilyLedger, Deleted *(shared)*        |

Family members share **one** family workbook by using the **same Family ID**
and being invited (Drive permission) from the wallet/master screens. The owner
creates it and shares it; every other member's app finds that one shared file
(it lives in the owner's Drive) and reads/writes the **same** copy — so the
common wallet and common expenses stay in sync across accounts. Saves merge the
latest remote copy first, so two members editing from different phones never
overwrite each other (the `Deleted` sheet tracks removals so deletes still
propagate).

---

## Prerequisites

1. **Install Flutter** (stable channel): https://docs.flutter.dev/get-started/install
   - Windows: download the SDK zip, extract to e.g. `C:\src\flutter`, add
     `C:\src\flutter\bin` to your `PATH`.
   - Verify: `flutter --version` and `flutter doctor`.
2. A device or emulator (Android Studio emulator, a physical phone with USB
   debugging, or Chrome for web).

## First-time setup

From this project folder (`family_finance`):

```bash
# 1. Generate the platform folders (android/ ios/ web/) for this app.
flutter create . --org net.ramrajcotton --project-name family_finance

# 2. Fetch dependencies.
flutter pub get

# 3. Run it.
flutter run            # pick a device when prompted
# or specifically:
flutter run -d chrome  # web
```

> `flutter create .` only adds the missing native scaffolding; it will **not**
> overwrite the `lib/` code in this repo.

---

## Google Sign-In + Drive configuration

You need OAuth credentials so the app can sign in and access Drive.

1. Go to the [Google Cloud Console](https://console.cloud.google.com/) →
   create a project.
2. **APIs & Services → Enable APIs** → enable **Google Drive API**.
3. **OAuth consent screen** → External → add your Google account as a **Test
   user** (so you can sign in before the app is verified).
   - **Add the `.../auth/drive` scope** under *Scopes* (the app uses the full
     Drive scope so invited members can open the shared family workbook). This
     is a sensitive/restricted scope: test users can use it immediately, but
     publishing to all users later needs Google's verification.
   - ⚠️ **Already signed in from an older build?** Sign out and sign back in
     once so Google grants the new Drive permission — silent sign-in keeps the
     old, narrower grant.
4. **Credentials → Create credentials → OAuth client ID** for each platform you
   target:

### Android
- Application type: **Android**.
- Package name: `net.ramrajcotton.family_finance` (must match `--org` above).
- SHA-1: get it with
  `cd android && ./gradlew signingReport` (or use the debug keystore SHA-1).
- No file download is needed for `google_sign_in` on Android, but ensure the
  OAuth client exists with the right SHA-1 + package name.
- Min SDK: set `minSdkVersion 21` in `android/app/build.gradle` if needed.

### iOS
- Application type: **iOS**, bundle ID `net.ramrajcotton.familyFinance`.
- Add the reversed client ID to `ios/Runner/Info.plist` URL schemes, e.g.:
  ```xml
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLSchemes</key>
      <array><string>com.googleusercontent.apps.YOUR_CLIENT_ID</string></array>
    </dict>
  </array>
  ```

### Web
- Application type: **Web**.
- Add your origin (e.g. `http://localhost:PORT`) to **Authorized JavaScript
  origins**.
- Put the web client ID in `web/index.html` inside `<head>`:
  ```html
  <meta name="google-signin-client_id" content="YOUR_WEB_CLIENT_ID.apps.googleusercontent.com">
  ```

> **Note:** Google Sign-In via `google_sign_in` targets **Android, iOS and
> Web**. Windows/macOS/Linux desktop are not supported by this plugin, so run
> the app on a phone/emulator or in Chrome.

---

## Biometric unlock (fingerprint / face)

The app lock supports an optional **fingerprint / face unlock** (toggle it on
under **menu → Appearance → App lock**, after a PIN is set; the PIN is always
the fallback). It uses the `local_auth` plugin, which needs a little native
setup in the generated platform folders:

**Android** (`android/app/src/main/...`)
- Make `MainActivity` extend `FlutterFragmentActivity` (not `FlutterActivity`),
  e.g. in `MainActivity.kt`:
  ```kotlin
  import io.flutter.embedding.android.FlutterFragmentActivity
  class MainActivity : FlutterFragmentActivity()
  ```
- Add the permission to `AndroidManifest.xml`:
  ```xml
  <uses-permission android:name="android.permission.USE_BIOMETRIC"/>
  ```

**iOS** — add to `ios/Runner/Info.plist`:
```xml
<key>NSFaceIDUsageDescription</key>
<string>Unlock Family Finance with Face ID</string>
```

After adding the dependency, run `flutter pub get`. On devices without
biometric hardware (or on web) the toggle simply doesn't appear and the PIN is
used as usual.

---

## Project structure

```
lib/
├── main.dart                  # app entry + auth-based routing
├── theme.dart                 # Material 3 theme
├── models/                    # data classes (one per Excel sheet)
│   ├── user_profile.dart  salary.dart  expense.dart
│   ├── emi.dart  target.dart  wallet_entry.dart  member.dart
│   ├── reminder.dart  category.dart  activity.dart  family_ledger.dart
├── services/
│   ├── auth_service.dart       # Google Sign-In + authed client
│   ├── drive_service.dart      # Drive v3: folder/file/upload/share
│   ├── excel_codec.dart        # rows <-> .xlsx bytes
│   └── finance_repository.dart # ties Drive + Excel together
├── state/
│   └── app_state.dart          # ChangeNotifier: single source of truth
├── utils/format.dart           # currency/date formatting, id gen
├── widgets/common.dart         # StatCard, PeriodPicker, DatePickerField…
└── screens/
    ├── login_screen.dart       dashboard_screen.dart   home_shell.dart
    ├── add_details_screen.dart salary_screen.dart      expenses_screen.dart
    ├── emi_screen.dart         reports_screen.dart      family_wallet_screen.dart
    ├── reminders_screen.dart   master_screen.dart
```

## Usage flow

1. **Sign in** with Google.
2. Open the avatar menu (top-right) → **My Details**, set your name, currency,
   and a **Family ID** (e.g. `sharma_family`) + family name to enable the
   shared wallet.
3. Add **Salary**, **Expenses**, and **EMIs**.
4. Use **Reports** to view month/year summaries and set **targets**.
5. On **Family**, top-up/spend the common wallet and **Invite** members; on
   **Users / Master**, manage the multi-user roster.

## Notes & next steps

- Saves are written to Drive after each change. For heavy use you may want to
  batch writes or add offline caching (e.g. `shared_preferences`/local file)
  and a sync indicator.
- Recurring **payment reminders** are now built in (in-app alerts on the
  Dashboard + a badged bell). A natural next step is delivering them as **device
  push notifications** (e.g. `flutter_local_notifications`), which needs a
  one-time native setup and is Android/iOS only.
- Possible future features: multi-currency conversion, budget rollover, CSV
  export, and per-member spending analytics on the family workbook.
