# Make it global — free Firebase setup (≈10 minutes, no credit card)

This switches the app from "Google Drive, test users only" to a **free cloud
backend (Cloud Firestore)** that works for **every Google user and family,
worldwide**, with no OAuth verification and no server to run.

The core app (Auth + Firestore) runs on Firebase's **Spark (free) plan** — **no
credit card** — and we deliberately avoid Cloud Functions (those need Blaze).

The **optional** file-attachment feature (receipt photos, exported PDFs, profile
pictures) uses **Cloud Storage**, which Firebase now only provisions on the
**Blaze (pay-as-you-go) plan**. Blaze keeps a free usage tier (≈5 GB stored,
1 GB/day download), so at household scale it stays **$0** — but it does require a
card on file. Setting it up is covered in the optional section below; skip it and
the app works exactly as before, just without attachments.

---

## 1. Create a free Firebase project

1. Go to <https://console.firebase.google.com> → **Add project**.
2. Name it (e.g. `family-finance`). Google Analytics is optional — you can
   skip it.

## 2. Turn on the two free services

**Authentication**
1. Build → **Authentication** → **Get started**.
2. **Sign-in method** → enable **Google** → Save.

**Firestore Database**
1. Build → **Firestore Database** → **Create database**.
2. Start in **production mode** (the rules below lock it down).
3. Location: pick the closest, e.g. **asia-south1 (Mumbai)**. (Can't be
   changed later.)

## 3. Register the apps

**Android**
1. Project settings (⚙️) → **Your apps** → **Add app → Android**.
2. Android package name: `net.ramrajcotton.family_finance`
3. Add your **debug SHA‑1** (the same fingerprint you registered before — get
   it from the existing keystore / `Generate Signing Keystore` workflow).
   Google sign-in won't work without it.

**Web**
1. Add app → **Web**. Give it any nickname. You'll get a `firebaseConfig`
   snippet — keep that tab open.

## 4. Generate the app config

From the project folder, with Flutter installed:

```bash
dart pub global activate flutterfire_cli
flutterfire configure        # choose your new project + Android & Web
```

This **overwrites `lib/firebase_options.dart`** with your real keys. That's the
only switch the app needs — on the next build it auto-detects the config and
stores everything in Firestore. Commit `lib/firebase_options.dart`.

> No `flutterfire` CLI? Open `lib/firebase_options.dart` and paste the values
> from your **Web** `firebaseConfig` (apiKey, appId, messagingSenderId,
> projectId, authDomain, storageBucket) into a `FirebaseOptions(...)` for each
> platform. The Android values come from *Project settings → Your apps →
> Android*.

## 5. Publish the security rules

Firebase console → **Firestore Database → Rules** → paste the contents of
[`firestore.rules`](firestore.rules) → **Publish**.

These keep each person's data private and isolate every family (a family is
reachable only via its secret code — see the file's header for details).

### 5b. (Optional) Enable file storage — receipts, PDFs, profile photos

Skip this whole subsection to stay 100% free with no card; attachments just
won't appear. To turn them on:

1. **Upgrade to Blaze:** console → ⚙️ **Usage and billing** → **Details &
   settings** → **Modify plan** → **Blaze**. Link a billing account (needs a
   card).
2. **Cap the spend so it can't surprise you:** console → **Budgets & alerts**
   (Google Cloud Billing) → create a budget of e.g. **$1** with email alerts at
   50/90/100%. At household scale you'll never approach the free tier anyway.
3. **Enable Storage:** Build → **Storage** → **Get started** → **production
   mode** → same location as Firestore.
4. **Publish the storage rules:** console → **Storage → Rules** → paste the
   contents of [`storage.rules`](storage.rules) → **Publish**. They keep every
   file private to the user who uploaded it (`users/{uid}/…`) and cap uploads to
   10 MB images/PDFs.
5. Make sure `flutterfire configure` (step 4) captured a **storageBucket** in
   `lib/firebase_options.dart` — it's added automatically once Storage exists.
   Re-run `flutterfire configure` if you enabled Storage afterwards.

That's it — the app detects the bucket and shows an **Attach receipt** option on
expenses; receipts open full-screen with pinch-to-zoom.

## 6. Point Google sign-in at Firebase

The app passes a Google **Web client ID** at build time via the GitHub Actions
variable `GOOGLE_SERVER_CLIENT_ID`. Set it to your **Firebase Web client ID**:

- Firebase console → Authentication → Sign-in method → Google → **Web SDK
  configuration → Web client ID**, **or**
- Google Cloud console → APIs & Services → Credentials → the auto-created
  *"Web client (auto created by Google Service)"*.

Update it under your repo → **Settings → Secrets and variables → Actions →
Variables**.

## 7. Build & run

- **Android:** push to `main` (or run the *Build Android APK* action). The CI
  already bumps `minSdk` to 23 (Firebase Auth's minimum) and signs the APK.
- **Web:** the *Deploy Web* action builds it; `firebase_core` injects the JS
  SDK automatically from `firebase_options.dart`.

That's it — sign in with any Google account, create a family (you're the
**head**), and share the **family code** to invite anyone, anywhere. People who
enter the code send you a **request to join**; nobody sees the family's data
until you **approve** them from **Users / Master**. Only the head can add,
remove, or change members — and the rules make the head role impossible to
hijack, even by someone who has the code.

> **Rolling out to existing users:** publish the updated `firestore.rules` and
> ship the matching app build together. The new rules only let the **head**
> change membership/roles, so older app versions (which rewrote the roster on
> every save) will lose the ability to write *shared family* data until updated.
> Personal data is unaffected.

---

### What changed in the app
- Sign-in now uses the **basic Google profile scope** (non-sensitive →
  global, no verification). The full Drive scope is gone.
- All data lives in **Firestore** (`users/{uid}` and
  `families/{familyId}/…`), with **offline support** built in.
- If `lib/firebase_options.dart` is still the placeholder, the app silently
  falls back to the old Drive storage — so nothing breaks before you finish
  this setup.
