'use strict';

const XLSX = require('xlsx');

const APP_FOLDER = 'FamilyFinance';

/** Mirror of the app's email sanitiser (lib/services/finance_repository.dart). */
function sanitizeEmail(email) {
  return email.replace(/[^a-zA-Z0-9._-]/g, '_');
}

/** Find a single file id by name inside an optional parent folder. */
async function findFileId(drive, name, parentId) {
  const q = [
    `name='${name.replace(/'/g, "\\'")}'`,
    "trashed=false",
    parentId ? `'${parentId}' in parents` : null,
  ].filter(Boolean).join(' and ');
  const res = await drive.files.list({ q, fields: 'files(id,name)', spaces: 'drive' });
  const files = res.data.files || [];
  return files.length ? files[0].id : null;
}

/** Download an xlsx file's bytes and parse it into { sheetName: [rowObjects] }. */
async function readWorkbook(drive, fileId) {
  const res = await drive.files.get(
    { fileId, alt: 'media' },
    { responseType: 'arraybuffer' },
  );
  const wb = XLSX.read(Buffer.from(res.data), { type: 'buffer' });
  const out = {};
  for (const name of wb.SheetNames) {
    const rows = XLSX.utils.sheet_to_json(wb.Sheets[name], { header: 1, raw: true });
    if (!rows.length) { out[name] = []; continue; }
    const headers = (rows[0] || []).map((h) => String(h));
    out[name] = rows.slice(1)
      .filter((r) => r.some((c) => String(c ?? '').trim() !== ''))
      .map((r) => Object.fromEntries(headers.map((h, i) => [h, r[i]])));
  }
  return out;
}

const num = (v) => {
  const n = typeof v === 'number' ? v : parseFloat(String(v ?? '').replace(/[, ]/g, ''));
  return Number.isFinite(n) ? n : 0;
};

/**
 * Build the full-snapshot model from a user's personal (and family) workbook.
 * `auth` is an authorised google OAuth2 client; `email` identifies the user.
 */
async function buildSnapshot(google, auth, email) {
  const drive = google.drive({ version: 'v3', auth });

  const folderId = await findFileId(drive, APP_FOLDER, null);
  if (!folderId) return null;

  const personalId = await findFileId(drive, `personal_${sanitizeEmail(email)}.xlsx`, folderId);
  if (!personalId) return null;

  const wb = await readWorkbook(drive, personalId);
  const profile = (wb['Profile'] || [])[0] || {};
  const currency = String(profile.currencyCode || 'INR');

  const now = new Date();
  const y = now.getFullYear();
  const m = now.getMonth() + 1;

  const inMonth = (r) => num(r.year) === y && num(r.month) === m;

  const salaries = wb['Salary'] || [];
  const expenses = wb['Expenses'] || [];
  const emis = wb['EMIs'] || [];
  const targets = wb['Targets'] || [];
  const activity = wb['Activity'] || [];

  const income = salaries.filter(inMonth).reduce((a, r) => a + num(r.amount), 0);
  const expense = expenses.filter(inMonth).reduce((a, r) => a + num(r.amount), 0);
  const savings = income - expense;

  // Category breakdown for the month.
  const catMap = {};
  for (const r of expenses.filter(inMonth)) {
    const c = String(r.category || 'Other');
    catMap[c] = (catMap[c] || 0) + num(r.amount);
  }
  const categories = Object.entries(catMap)
    .map(([name, amount]) => ({ name, amount }))
    .sort((a, b) => b.amount - a.amount);

  // EMIs.
  const open = emis.filter((r) => num(r.paidMonths) < num(r.totalMonths));
  const emiMonthly = open.reduce((a, r) => a + num(r.monthlyAmount), 0);
  const emiRemaining = emis.reduce(
    (a, r) => a + num(r.monthlyAmount) * Math.max(0, num(r.totalMonths) - num(r.paidMonths)),
    0,
  );
  const soon = new Date(now.getTime() + 14 * 864e5);
  const dueSoon = open.map((r) => {
    const start = new Date(r.startDate || 0);
    const due = new Date(start.getFullYear(), start.getMonth() + num(r.paidMonths), start.getDate());
    return { name: String(r.name || 'EMI'), amount: num(r.monthlyAmount), due };
  }).filter((e) => e.due >= new Date(now.toDateString()) && e.due <= soon)
    .sort((a, b) => a.due - b.due);

  const target = targets.find((r) => num(r.year) === y && num(r.month) === m) || null;

  // Recent changes: everything since the start of yesterday.
  const since = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
  const recent = activity
    .map((r) => ({
      ts: new Date(r.timestamp || 0),
      action: String(r.action || ''),
      type: String(r.type || ''),
      description: String(r.description || ''),
      amount: num(r.amount),
    }))
    .filter((a) => a.ts >= since)
    .sort((a, b) => b.ts - a.ts);

  // Shared family wallet balance (optional).
  let walletBalance = null;
  const familyId = String(profile.familyId || '');
  if (familyId) {
    const famId = await findFileId(drive, `family_${familyId}.xlsx`, folderId);
    if (famId) {
      const fam = await readWorkbook(drive, famId);
      const wallet = fam['Wallet'] || [];
      walletBalance = wallet.reduce(
        (a, r) => a + (String(r.direction) === 'spend' ? -num(r.amount) : num(r.amount)),
        0,
      );
    }
  }

  return {
    email,
    name: String(profile.displayName || email),
    currency,
    period: now.toLocaleString('en-US', { month: 'long', year: 'numeric' }),
    income, expense, savings,
    savingsTarget: target ? num(target.savingsTarget) : 0,
    spendingLimit: target ? num(target.spendingLimit) : 0,
    categories,
    emiMonthly, emiRemaining, activeEmis: open.length, dueSoon,
    walletBalance,
    recent,
  };
}

function money(v, currency) {
  try {
    return new Intl.NumberFormat('en-IN', { style: 'currency', currency }).format(v);
  } catch {
    return `${currency} ${Number(v).toFixed(2)}`;
  }
}

/** Render the snapshot as a responsive HTML email. */
function renderHtml(s) {
  const c = s.currency;
  const row = (label, value, color) =>
    `<tr><td style="padding:8px 0;color:#5b6b69">${label}</td>
     <td style="padding:8px 0;text-align:right;font-weight:700;color:${color || '#0f1514'}">${value}</td></tr>`;

  const cats = s.categories.slice(0, 8).map((x) =>
    `<tr><td style="padding:6px 0">${x.name}</td>
     <td style="padding:6px 0;text-align:right">${money(x.amount, c)}</td></tr>`).join('') ||
    '<tr><td style="padding:6px 0;color:#8a9b98">No expenses yet this month</td></tr>';

  const due = s.dueSoon.map((d) =>
    `<tr><td style="padding:6px 0">${d.name}</td>
     <td style="padding:6px 0;text-align:right">${money(d.amount, c)} · ${d.due.toLocaleDateString('en-IN', { day: '2-digit', month: 'short' })}</td></tr>`).join('') ||
    '<tr><td style="padding:6px 0;color:#8a9b98">Nothing due in the next 14 days</td></tr>';

  const recent = s.recent.slice(0, 15).map((a) =>
    `<tr><td style="padding:6px 0">${a.action} · ${a.type}<div style="color:#8a9b98;font-size:12px">${a.description}</div></td>
     <td style="padding:6px 0;text-align:right">${a.amount > 0 ? money(a.amount, c) : ''}</td></tr>`).join('') ||
    '<tr><td style="padding:6px 0;color:#8a9b98">No changes since yesterday</td></tr>';

  return `<!doctype html><html><body style="margin:0;background:#f4f7f6;font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;color:#0f1514">
  <div style="max-width:560px;margin:0 auto;padding:24px">
    <div style="background:linear-gradient(135deg,#13726b,#0a3f3b);border-radius:20px;padding:24px;color:#fff">
      <div style="font-size:13px;opacity:.85">Family Finance · ${s.period}</div>
      <div style="font-size:22px;font-weight:800;margin-top:4px">Good morning, ${s.name.split(' ')[0]} 👋</div>
      <div style="font-size:13px;opacity:.9;margin-top:6px">Here's your money snapshot.</div>
    </div>

    <div style="background:#fff;border:1px solid #e2e9e7;border-radius:16px;padding:18px;margin-top:16px">
      <table style="width:100%;border-collapse:collapse;font-size:14px">
        ${row('Income (this month)', money(s.income, c), '#1e8e5a')}
        ${row('Expenses (this month)', money(s.expense, c), '#d0463b')}
        ${row('Savings', money(s.savings, c), s.savings >= 0 ? '#1e8e5a' : '#d0463b')}
        ${s.savingsTarget > 0 ? row('Savings target', money(s.savingsTarget, c)) : ''}
        ${s.spendingLimit > 0 ? row('Spending limit', money(s.spendingLimit, c)) : ''}
        ${row('EMI / month', money(s.emiMonthly, c))}
        ${row('EMI remaining', money(s.emiRemaining, c))}
        ${s.walletBalance != null ? row('Family wallet', money(s.walletBalance, c), '#3949ab') : ''}
      </table>
    </div>

    <div style="background:#fff;border:1px solid #e2e9e7;border-radius:16px;padding:18px;margin-top:16px">
      <div style="font-weight:700;margin-bottom:6px">Spending by category</div>
      <table style="width:100%;border-collapse:collapse;font-size:14px">${cats}</table>
    </div>

    <div style="background:#fff;border:1px solid #e2e9e7;border-radius:16px;padding:18px;margin-top:16px">
      <div style="font-weight:700;margin-bottom:6px">EMIs due soon</div>
      <table style="width:100%;border-collapse:collapse;font-size:14px">${due}</table>
    </div>

    <div style="background:#fff;border:1px solid #e2e9e7;border-radius:16px;padding:18px;margin-top:16px">
      <div style="font-weight:700;margin-bottom:6px">Recent changes</div>
      <table style="width:100%;border-collapse:collapse;font-size:14px">${recent}</table>
    </div>

    <div style="text-align:center;color:#8a9b98;font-size:12px;margin-top:18px">
      Sent by your Family Finance daily report.
    </div>
  </div></body></html>`;
}

module.exports = { buildSnapshot, renderHtml, sanitizeEmail };
