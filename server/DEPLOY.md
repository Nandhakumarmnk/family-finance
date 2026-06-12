# Daily report backend — deploy guide

A Google Cloud Functions (gen2) backend that emails every user a daily
"full snapshot" of their finances, read from their own Google Drive workbook.

```
App (sign-in)  ──serverAuthCode──▶  linkUser  ──▶  Firestore {email, refreshToken}
Cloud Scheduler (daily) ──▶ sendDailyReports ──▶ Drive read ──▶ Resend email
```

## 0. Prerequisites
- The `gcloud` CLI installed and logged in: `gcloud auth login`
- Project selected: `gcloud config set project family-finance-499112`
- **Billing enabled** on the project (free tier covers this usage, but a card is required).
- A [Resend](https://resend.com) account → **API key**. For real delivery, verify a
  sending domain; for a quick test, `onboarding@resend.dev` delivers only to your
  own Resend account email.

## 1. Enable APIs
```bash
gcloud services enable \
  cloudfunctions.googleapis.com run.googleapis.com cloudbuild.googleapis.com \
  cloudscheduler.googleapis.com firestore.googleapis.com drive.googleapis.com \
  eventarc.googleapis.com
```

## 2. Create Firestore (native mode, once)
```bash
gcloud firestore databases create --location=asia-south1
```

## 3. Get your Web client secret
APIs & Services → Credentials → your **Web application** client → copy the
**Client ID** and **Client secret** (the one showing `****yc9D`).

## 4. Deploy the two functions
From the `server/` folder:

```bash
# Called by the app — must be public.
gcloud functions deploy linkUser \
  --gen2 --runtime=nodejs20 --region=asia-south1 \
  --source=. --entry-point=linkUser --trigger-http --allow-unauthenticated \
  --set-env-vars=GOOGLE_CLIENT_ID=YOUR_WEB_CLIENT_ID,GOOGLE_CLIENT_SECRET=YOUR_WEB_SECRET,RESEND_API_KEY=YOUR_RESEND_KEY,"REPORT_FROM=Family Finance <onboarding@resend.dev>"

# Called only by Scheduler — keep private.
gcloud functions deploy sendDailyReports \
  --gen2 --runtime=nodejs20 --region=asia-south1 \
  --source=. --entry-point=sendDailyReports --trigger-http --no-allow-unauthenticated \
  --set-env-vars=GOOGLE_CLIENT_ID=YOUR_WEB_CLIENT_ID,GOOGLE_CLIENT_SECRET=YOUR_WEB_SECRET,RESEND_API_KEY=YOUR_RESEND_KEY,"REPORT_FROM=Family Finance <onboarding@resend.dev>"
```

Note the **linkUser URL** printed at the end (looks like
`https://asia-south1-family-finance-499112.cloudfunctions.net/linkUser`).

## 5. Wire the app to linkUser
In the GitHub repo: **Settings → Secrets and variables → Actions → Variables** →
new variable **`GOOGLE_BACKEND_URL`** = the linkUser URL from step 4.
Then re-run **Deploy Web** / **Build APK** so the app posts the offline code on sign-in.

## 6. Schedule the daily send (e.g. 7:00 AM IST)
```bash
# Service account Scheduler uses to call the private function with an OIDC token.
gcloud iam service-accounts create scheduler-invoker --display-name="Scheduler Invoker"

SA="scheduler-invoker@family-finance-499112.iam.gserviceaccount.com"
URL="$(gcloud functions describe sendDailyReports --gen2 --region=asia-south1 --format='value(serviceConfig.uri)')"

gcloud run services add-iam-policy-binding sendDailyReports \
  --region=asia-south1 --member="serviceAccount:$SA" --role=roles/run.invoker

gcloud scheduler jobs create http daily-finance-report \
  --location=asia-south1 --schedule="0 7 * * *" --time-zone="Asia/Kolkata" \
  --uri="$URL" --http-method=POST \
  --oidc-service-account-email="$SA" --oidc-token-audience="$URL"
```

## 7. Test it
- Sign in to the app once (so `linkUser` stores your refresh token). Check
  Firestore → `subscribers` has your email.
- Trigger a send now: `gcloud scheduler jobs run daily-finance-report --location=asia-south1`
- Check your inbox (and `gcloud functions logs read sendDailyReports --gen2 --region=asia-south1`).

## Gotchas
- **`no_refresh_token`** from linkUser: Google only issues a refresh token on the
  *first* consent. Remove the app at
  [myaccount.google.com/permissions](https://myaccount.google.com/permissions),
  sign in again.
- **`redirect_uri_mismatch`** redeeming the code: the app's offline code expects the
  `postmessage` redirect. If your platform needs a different value, redeploy with
  `OAUTH_REDIRECT=<value>` and add that exact URI to the Web client's
  *Authorized redirect URIs*.
- **`drive.file` visibility**: the backend (Web client) reads files the project's
  app created. If reads return "no_data" even though the file exists, the file may
  have been created under a different OAuth client — confirm the app and backend
  use the **same** project's Web client ID.
- **Cost**: Cloud Functions + Scheduler + Firestore for a handful of users sit
  comfortably in the always-free tier.
