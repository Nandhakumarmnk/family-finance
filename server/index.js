'use strict';

const functions = require('@google-cloud/functions-framework');
const { Firestore } = require('@google-cloud/firestore');
const { google } = require('googleapis');
const { OAuth2Client } = require('google-auth-library');

const { buildSnapshot, renderHtml } = require('./lib/report');

const db = new Firestore();
const SUBSCRIBERS = 'subscribers';

const CLIENT_ID = process.env.GOOGLE_CLIENT_ID;
const CLIENT_SECRET = process.env.GOOGLE_CLIENT_SECRET;
// google_sign_in returns an auth code intended to be redeemed with the
// "postmessage" pseudo-redirect. If your platform needs a different value,
// override with OAUTH_REDIRECT.
const REDIRECT = process.env.OAUTH_REDIRECT || 'postmessage';

const RESEND_API_KEY = process.env.RESEND_API_KEY;
const REPORT_FROM = process.env.REPORT_FROM; // e.g. "Family Finance <reports@yourdomain.com>"

function oauthClient() {
  return new OAuth2Client(CLIENT_ID, CLIENT_SECRET, REDIRECT);
}

function cors(res) {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');
}

// ---------------------------------------------------------------------------
// linkUser — called by the app once after sign-in with an offline serverAuthCode.
// Exchanges it for a refresh token and stores it keyed by the verified email.
// ---------------------------------------------------------------------------
functions.http('linkUser', async (req, res) => {
  cors(res);
  if (req.method === 'OPTIONS') return res.status(204).send('');
  if (req.method !== 'POST') return res.status(405).send('POST only');

  try {
    const { serverAuthCode } = req.body || {};
    if (!serverAuthCode) return res.status(400).json({ error: 'serverAuthCode required' });

    const client = oauthClient();
    const { tokens } = await client.getToken(serverAuthCode);

    // Verify identity from the id_token rather than trusting client input.
    const ticket = await client.verifyIdToken({ idToken: tokens.id_token, audience: CLIENT_ID });
    const email = ticket.getPayload().email;

    if (!tokens.refresh_token) {
      // Google only returns a refresh token the first time consent is granted.
      // If we already have one stored, keep it; otherwise ask the user to
      // revoke access and sign in again.
      const existing = await db.collection(SUBSCRIBERS).doc(email).get();
      if (!existing.exists || !existing.data().refreshToken) {
        return res.status(409).json({
          error: 'no_refresh_token',
          hint: 'Remove app access at myaccount.google.com/permissions and sign in again.',
        });
      }
      return res.json({ ok: true, email, note: 'kept existing refresh token' });
    }

    await db.collection(SUBSCRIBERS).doc(email).set({
      email,
      refreshToken: tokens.refresh_token,
      enabled: true,
      updatedAt: Firestore.Timestamp.now(),
    }, { merge: true });

    res.json({ ok: true, email });
  } catch (e) {
    console.error('linkUser failed', e);
    res.status(500).json({ error: String(e.message || e) });
  }
});

// ---------------------------------------------------------------------------
// sendDailyReports — invoked by Cloud Scheduler each morning (authenticated).
// Builds and emails the full-snapshot report for every enabled subscriber.
// ---------------------------------------------------------------------------
functions.http('sendDailyReports', async (req, res) => {
  const results = [];
  try {
    const snap = await db.collection(SUBSCRIBERS).where('enabled', '==', true).get();
    for (const doc of snap.docs) {
      const { email, refreshToken } = doc.data();
      try {
        const client = oauthClient();
        client.setCredentials({ refresh_token: refreshToken });
        const snapshot = await buildSnapshot(google, client, email);
        if (!snapshot) { results.push({ email, status: 'no_data' }); continue; }
        await sendEmail(email, `Your money snapshot — ${snapshot.period}`, renderHtml(snapshot));
        results.push({ email, status: 'sent' });
      } catch (e) {
        console.error(`report failed for ${email}`, e);
        results.push({ email, status: 'error', error: String(e.message || e) });
      }
    }
    res.json({ ok: true, count: results.length, results });
  } catch (e) {
    console.error('sendDailyReports failed', e);
    res.status(500).json({ error: String(e.message || e) });
  }
});

async function sendEmail(to, subject, html) {
  const resp = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ from: REPORT_FROM, to, subject, html }),
  });
  if (!resp.ok) {
    throw new Error(`Resend ${resp.status}: ${await resp.text()}`);
  }
}
