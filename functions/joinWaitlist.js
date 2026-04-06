/**
 * joinWaitlist - Cloud Function
 *
 * HTTPS endpoint called by the public marketing site (peezymove.com)
 * when a visitor submits the "Join Waitlist" form.
 *
 * Flow:
 *   1. Accept POST { email } from peezymove.com (CORS enabled)
 *   2. Validate + normalize email
 *   3. Deduplicate via Firestore (doc id = normalized email)
 *   4. Write to `waitlistSignups` collection
 *   5. Send warm founder welcome email to user (from adam@peezymove.com)
 *   6. Send admin notification to adampow23@gmail.com
 *   7. Return { ok: true, alreadySignedUp: boolean }
 *
 * REQUIREMENTS:
 *   - Reuses existing GMAIL_APP_PASSWORD secret (already configured for packageInventory)
 *   - Reuses existing nodemailer dependency
 *   - Zero new DNS records, zero new vendors
 *
 * SECURITY:
 *   - Public endpoint (no auth) — must be, since peezymove.com has no Firebase auth context
 *   - Rate limited in-memory per IP (10 requests / minute)
 *   - Firestore dedup prevents double-emails on accidental double-submit
 *   - Email sending failures do NOT lose the signup (Firestore write happens first)
 */

const { onRequest } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const nodemailer = require('nodemailer');

const ADMIN_EMAIL = 'adam@peezymove.com';
const ADMIN_NOTIFY_EMAIL = 'adampow23@gmail.com';
const COLLECTION = 'waitlistSignups';

// ─────────────────────────────────────────────
// Nodemailer transporter (lazy, mirrors packageInventory.js)
// ─────────────────────────────────────────────

let transporter = null;

function getTransporter() {
  if (!transporter) {
    const appPassword = process.env.GMAIL_APP_PASSWORD;
    if (!appPassword) {
      throw new Error('GMAIL_APP_PASSWORD environment variable is required');
    }
    transporter = nodemailer.createTransport({
      host: 'smtp.gmail.com',
      port: 465,
      secure: true,
      auth: {
        user: ADMIN_EMAIL,
        pass: appPassword
      }
    });
  }
  return transporter;
}

// ─────────────────────────────────────────────
// Rate limiting (in-memory, per IP, resets on cold start)
// ─────────────────────────────────────────────

const rateLimitMap = new Map();
const RATE_LIMIT_WINDOW_MS = 60 * 1000; // 1 minute
const RATE_LIMIT_MAX = 10;               // 10 submits per IP per minute

function checkRateLimit(ip) {
  const now = Date.now();
  const entry = rateLimitMap.get(ip);
  if (!entry || now - entry.windowStart > RATE_LIMIT_WINDOW_MS) {
    rateLimitMap.set(ip, { windowStart: now, count: 1 });
    return true;
  }
  if (entry.count >= RATE_LIMIT_MAX) return false;
  entry.count++;
  return true;
}

// ─────────────────────────────────────────────
// Email validation + normalization
// ─────────────────────────────────────────────

// Pragmatic RFC 5322-ish regex. Not exhaustive, but catches ~99% of real-world bad input.
const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MAX_EMAIL_LENGTH = 254; // RFC 3696 errata

function normalizeEmail(raw) {
  if (typeof raw !== 'string') return null;
  const trimmed = raw.trim().toLowerCase();
  if (trimmed.length === 0 || trimmed.length > MAX_EMAIL_LENGTH) return null;
  if (!EMAIL_REGEX.test(trimmed)) return null;
  return trimmed;
}

// Firestore doc IDs cannot contain "/" or ".." or be empty.
// We hash-escape dots to keep the email as the natural dedup key while staying safe.
function emailToDocId(email) {
  return email.replace(/\./g, ',').replace(/\//g, '_');
}

// ─────────────────────────────────────────────
// Cloud Function
// ─────────────────────────────────────────────

exports.joinWaitlist = onRequest(
  {
    timeoutSeconds: 30,
    memory: '256MiB',
    cors: true, // Allow cross-origin from peezymove.com (and anywhere else — safe for a public waitlist endpoint)
    secrets: ['GMAIL_APP_PASSWORD']
  },
  async (req, res) => {
    // 1. Method check
    if (req.method === 'OPTIONS') {
      // CORS preflight handled by the framework, but be explicit
      res.status(204).send('');
      return;
    }
    if (req.method !== 'POST') {
      res.status(405).json({ ok: false, error: 'Method not allowed' });
      return;
    }

    // 2. Rate limit by IP
    const ip =
      (req.headers['x-forwarded-for'] || '').toString().split(',')[0].trim() ||
      req.ip ||
      'unknown';
    if (!checkRateLimit(ip)) {
      console.warn('joinWaitlist: rate limit exceeded for', ip);
      res.status(429).json({ ok: false, error: 'Too many requests. Try again in a minute.' });
      return;
    }

    // 3. Parse + validate email
    const rawEmail = req.body && req.body.email;
    const email = normalizeEmail(rawEmail);
    if (!email) {
      res.status(400).json({ ok: false, error: 'Please enter a valid email address.' });
      return;
    }

    const db = admin.firestore();
    const docId = emailToDocId(email);
    const docRef = db.collection(COLLECTION).doc(docId);

    try {
      // 4. Dedupe check — if they already signed up, succeed silently (no second email)
      const existing = await docRef.get();
      if (existing.exists) {
        console.log(`joinWaitlist: duplicate signup for ${email}, skipping email`);
        res.status(200).json({ ok: true, alreadySignedUp: true });
        return;
      }

      // 5. Write the signup FIRST (so we never lose a signup if email fails)
      const userAgent = (req.headers['user-agent'] || '').toString().slice(0, 500);
      const referer = (req.headers['referer'] || req.headers['referrer'] || '').toString().slice(0, 500);
      await docRef.set({
        email,
        source: 'peezymove.com',
        userAgent,
        referer,
        ip,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        welcomeEmailSent: false,
        adminNotified: false
      });

      // 6. Send welcome email to user (warm founder note)
      let welcomeSent = false;
      try {
        const mailer = getTransporter();
        await mailer.sendMail({
          from: `"Adam from Peezy" <${ADMIN_EMAIL}>`,
          to: email,
          replyTo: ADMIN_EMAIL,
          subject: "You're on the Peezy list — and I wanted to say hi",
          text: buildWelcomeText(),
          html: buildWelcomeHTML()
        });
        welcomeSent = true;
      } catch (mailErr) {
        console.error('joinWaitlist: welcome email failed for', email, mailErr.message);
        // Do not fail the request — the signup is still stored.
      }

      // 7. Notify admin
      let adminNotified = false;
      try {
        const mailer = getTransporter();
        await mailer.sendMail({
          from: `"Peezy Waitlist" <${ADMIN_EMAIL}>`,
          to: ADMIN_NOTIFY_EMAIL,
          subject: `New Peezy waitlist signup: ${email}`,
          text: `New signup on peezymove.com\n\nEmail: ${email}\nTime: ${new Date().toISOString()}\nSource: peezymove.com\nUser-Agent: ${userAgent}\nIP: ${ip}`,
          html: buildAdminHTML({ email, userAgent, ip })
        });
        adminNotified = true;
      } catch (notifyErr) {
        console.error('joinWaitlist: admin notification failed:', notifyErr.message);
      }

      // 8. Patch the doc with email status (fire-and-forget semantics fine here)
      await docRef.update({
        welcomeEmailSent: welcomeSent,
        adminNotified: adminNotified
      });

      console.log(`joinWaitlist: new signup ${email} (welcome=${welcomeSent}, notified=${adminNotified})`);
      res.status(200).json({ ok: true, alreadySignedUp: false });
    } catch (err) {
      console.error('joinWaitlist error:', err.message, err.stack);
      res.status(500).json({ ok: false, error: 'Something went wrong on our end. Please try again.' });
    }
  }
);

// ─────────────────────────────────────────────
// Email content — warm founder note from Adam
// ─────────────────────────────────────────────

function buildWelcomeText() {
  return [
    "Hey,",
    "",
    "Adam here — founder of Peezy. Thanks for jumping on the waitlist.",
    "",
    "Quick story: I built Peezy because I've moved a lot, and every single time the same thing happened — forty browser tabs, a notebook full of to-dos, and the creeping feeling I was forgetting something important. So I set out to build the thing I wished existed: a moving concierge in your pocket that actually handles the boring stuff for you.",
    "",
    "You're early, which means you'll be one of the first people to get access when we open the doors. I'll send you a note the moment that happens — and in the meantime I might ping you once or twice with a behind-the-scenes look at what we're building.",
    "",
    "If you want to tell me about your upcoming move, or just say hi, hit reply. I read every email personally.",
    "",
    "Talk soon,",
    "Adam",
    "Founder, Peezy",
    "peezymove.com"
  ].join("\n");
}

function buildWelcomeHTML() {
  return `<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Welcome to Peezy</title></head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 560px; margin: 0 auto; padding: 32px 20px; color: #1a1a1a; line-height: 1.6;">

  <div style="background: #FFC233; padding: 20px 24px; border-radius: 12px; margin-bottom: 28px;">
    <h1 style="margin: 0; font-size: 22px; color: #1a1a1a;">You're on the list 🎉</h1>
    <p style="margin: 6px 0 0; color: #1a1a1a; opacity: 0.75; font-size: 14px;">Welcome to Peezy</p>
  </div>

  <p style="font-size: 16px; margin: 0 0 16px;">Hey,</p>

  <p style="font-size: 16px; margin: 0 0 16px;">
    Adam here — founder of Peezy. Thanks for jumping on the waitlist.
  </p>

  <p style="font-size: 16px; margin: 0 0 16px;">
    Quick story: I built Peezy because I've moved a lot, and every single time the same thing happened — forty browser tabs, a notebook full of to-dos, and the creeping feeling I was forgetting something important. So I set out to build the thing I wished existed: a moving concierge in your pocket that actually handles the boring stuff for you.
  </p>

  <p style="font-size: 16px; margin: 0 0 16px;">
    You're early, which means you'll be one of the first people to get access when we open the doors. I'll send you a note the moment that happens — and in the meantime I might ping you once or twice with a behind-the-scenes look at what we're building.
  </p>

  <p style="font-size: 16px; margin: 0 0 16px;">
    If you want to tell me about your upcoming move, or just say hi, hit reply. I read every email personally.
  </p>

  <p style="font-size: 16px; margin: 24px 0 4px;">Talk soon,</p>
  <p style="font-size: 16px; margin: 0 0 24px;">
    <strong>Adam</strong><br>
    <span style="color: #666;">Founder, Peezy</span><br>
    <a href="https://peezymove.com" style="color: #1a1a1a; text-decoration: none; border-bottom: 1px solid #FFC233;">peezymove.com</a>
  </p>

  <hr style="border: none; border-top: 1px solid #eee; margin: 32px 0 16px;">
  <p style="font-size: 12px; color: #999; margin: 0;">
    You're receiving this because you signed up at peezymove.com. Not expecting this email? Just ignore it — we won't write again unless you're still interested.
  </p>
</body>
</html>`;
}

function buildAdminHTML({ email, userAgent, ip }) {
  return `<!DOCTYPE html>
<html>
<body style="font-family: -apple-system, sans-serif; max-width: 560px; margin: 0 auto; padding: 24px; color: #1a1a1a;">
  <div style="background: #FFC233; padding: 16px 20px; border-radius: 10px; margin-bottom: 20px;">
    <h2 style="margin: 0; font-size: 18px;">New Peezy waitlist signup</h2>
  </div>
  <table style="width: 100%; font-size: 14px;">
    <tr><td style="padding: 6px 0; font-weight: 600; width: 110px;">Email</td><td><a href="mailto:${email}">${email}</a></td></tr>
    <tr><td style="padding: 6px 0; font-weight: 600;">Time</td><td>${new Date().toISOString()}</td></tr>
    <tr><td style="padding: 6px 0; font-weight: 600;">Source</td><td>peezymove.com</td></tr>
    <tr><td style="padding: 6px 0; font-weight: 600;">IP</td><td>${ip}</td></tr>
    <tr><td style="padding: 6px 0; font-weight: 600; vertical-align: top;">User-Agent</td><td style="font-family: monospace; font-size: 12px; color: #666;">${userAgent || '—'}</td></tr>
  </table>
</body>
</html>`;
}
