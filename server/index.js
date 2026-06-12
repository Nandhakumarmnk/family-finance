'use strict';

const functions = require('@google-cloud/functions-framework');
const { Firestore } = require('@google-cloud/firestore');
const { google } = require('googleapis');
const { OAuth2Client } = require('google-auth-library');

const {
  buildSnapshot,
  renderHtml,
  buildFamilySnapshot,
  renderFamilyHtml,
} = require('./lib/report');

const db = new Firestore();
const SUBSCRIBERS = 'subscribers';

const CLIENT_ID = process.env.GOOGLE_CLIENT_ID;
const CLIENT_SECRET = process.env.GOOGLE_CLIENT_SECRET;
// google_sign_in returns an auth code intended to be redeemed with the
// "postmessage" pseudo-redirect. Override with OAUTH_REDIRECT if needed.
const REDIRECT = process.env.OAUTH_REDIRECT || 'postmessage';

const RESEND_API_KEY = process.env.RESEND_API_KEY;
const REPORT_FROM = process.env.REPORT_FROM; // "Family Finance <reports@yourdomain.com>"

function oauthClient() {
  return new OAuth2Client(CLIENT_ID, CLIENT_SECRET, REDIRECT);
}

function cors(res) {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');
}

async function sendEmail(to, subject, html) {
  const resp = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ from: REPORT_FROM, to, subject, html }),
  });
  if (!resp.ok) throw new Error(`Resend ${resp.status}: ${await resp.text()}`);
}

/** Build + email the personal (and, for a parent, family) report for one user. */
async function emailReportsFor({ email, refreshToken, role, familyId }) {
  const client = oauthClient();
  client.setCredentials({ refresh_token: refreshToken });

  const personal = await buildSnapshot(google, client, email);
  if (personal) {
    await sendEmail(email, `Your money snapshot — ${personal.period}`, renderHtml(personal));
  }
  if (role === 'parent' && familyId) {
    const fam = await buildFamilySnapshot(google, client, familyId, personal?.currency || 'INR');
    if (fam) await sendEmail(email, `Family snapshot — ${fam.period}`, renderFamilyHtml(fam));
  }
  return Boolean(personal);
}

// ---------------------------------------------------------------------------
// api — single public endpoint the app calls. Routes on body.action:
//   { action: 'link',    serverAuthCode, familyId, role }  (called at sign-in)
//   { action: 'sendNow', idToken }                         (the "email me now" button)
// ---------------------------------------------------------------------------
functions.http('api', async (req, res) => {
  cors(res);
  if (req.method === 'OPTIONS') return res.status(204).send('');
  if (req.method !== 'POST') return res.status(405).send('POST only');

  const action = (req.body && req.body.action) || 'link';
  try {
    if (action === 'link') return await handleLink(req, res);
    if (action === 'sendNow') return await handleSendNow(req, res);
    return res.status(400).json({ error: `unknown action: ${action}` });
  } catch (e) {
    console.error(`api(${action}) failed`, e);
    return res.status(500).json({ error: String(e.message || e) });
  }
});

async function handleLink(req, res) {
  const { serverAuthCode, familyId = '', role = 'member' } = req.body || {};
  if (!serverAuthCode) return res.status(400).json({ error: 'serverAuthCode required' });

  const client = oauthClient();
  const { tokens } = await client.getToken(serverAuthCode);

  // Verify identity from the id_token rather than trusting client input.
  const ticket = await client.verifyIdToken({ idToken: tokens.id_token, audience: CLIENT_ID });
  const email = ticket.getPayload().email;

  if (!tokens.refresh_token) {
    const existing = await db.collection(SUBSCRIBERS).doc(email).get();
    if (!existing.exists || !existing.data().refreshToken) {
      return res.status(409).json({
        error: 'no_refresh_token',
        hint: 'Remove app access at myaccount.google.com/permissions and sign in again.',
      });
    }
    await db.collection(SUBSCRIBERS).doc(email).set(
      { familyId, role, updatedAt: Firestore.Timestamp.now() }, { merge: true });
    return res.json({ ok: true, email, note: 'kept existing refresh token' });
  }

  await db.collection(SUBSCRIBERS).doc(email).set({
    email,
    refreshToken: tokens.refresh_token,
    familyId,
    role,
    enabled: true,
    updatedAt: Firestore.Timestamp.now(),
  }, { merge: true });

  return res.json({ ok: true, email });
}

async function handleSendNow(req, res) {
  const { idToken } = req.body || {};
  if (!idToken) return res.status(400).json({ error: 'idToken required' });

  const ticket = await oauthClient().verifyIdToken({ idToken, audience: CLIENT_ID });
  const email = ticket.getPayload().email;

  const doc = await db.collection(SUBSCRIBERS).doc(email).get();
  if (!doc.exists || !doc.data().refreshToken) {
    return res.status(409).json({ error: 'not_linked', hint: 'Sign in once with the backend configured.' });
  }
  const sent = await emailReportsFor(doc.data());
  return res.json({ ok: true, sent });
}

// ---------------------------------------------------------------------------
// sendDailyReports — invoked by Cloud Scheduler each morning (authenticated).
// ---------------------------------------------------------------------------
functions.http('sendDailyReports', async (req, res) => {
  const results = [];
  try {
    const snap = await db.collection(SUBSCRIBERS).where('enabled', '==', true).get();
    for (const doc of snap.docs) {
      const data = doc.data();
      try {
        const ok = await emailReportsFor(data);
        results.push({ email: data.email, status: ok ? 'sent' : 'no_data', role: data.role });
      } catch (e) {
        console.error(`report failed for ${data.email}`, e);
        results.push({ email: data.email, status: 'error', error: String(e.message || e) });
      }
    }
    res.json({ ok: true, count: results.length, results });
  } catch (e) {
    console.error('sendDailyReports failed', e);
    res.status(500).json({ error: String(e.message || e) });
  }
});
