/**
 * Best-effort founder notifications for new support messages.
 * Each channel is enabled only when its SUPPORT_NOTIFY_* destination is set.
 */

const nodemailer = require('nodemailer');
const twilio = require('twilio');
const logger = require('firebase-functions/logger');
const { withOutboundLease } = require('./accountDeletionFence');

const SUPPORT_FROM_EMAIL = 'adam@peezymove.com';
const SMTP_TIMEOUT_MS = 8000;
const SMS_TIMEOUT_MS = 8000;

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
      connectionTimeout: SMTP_TIMEOUT_MS, greetingTimeout: SMTP_TIMEOUT_MS, socketTimeout: SMTP_TIMEOUT_MS, // C5: provider timeout ≤ 300 s
      auth: {
        user: SUPPORT_FROM_EMAIL,
        pass: appPassword
      }
    });
  }
  return transporter;
}

async function sendEmail({ uid, textPreview, taskTitle }, deps) {
  const destination = process.env.SUPPORT_NOTIFY_EMAIL;
  if (!destination) return;

  try {
    const subject = taskTitle
      ? `New Peezy support message — ${taskTitle}`
      : 'New Peezy support message';
    const taskLine = taskTitle ? `Task: ${taskTitle}\n` : '';

    // C6.2: the send runs under a support_email outbound lease keyed by the sender's root.
    await withOutboundLease(deps, { uid, channel: 'support_email' }, () => getTransporter().sendMail({
      from: `"Peezy Move" <${SUPPORT_FROM_EMAIL}>`,
      to: destination,
      subject,
      text: `User: ${uid}\n${taskLine}\n${textPreview}`
    }));
  } catch (error) {
    logger.warn('SUPPORT_EMAIL_FAILED');
  }
}

async function sendSms({ uid, textPreview, taskTitle }, deps) {
  const destination = process.env.SUPPORT_NOTIFY_SMS;
  if (!destination) return;

  try {
    const accountSid = process.env.TWILIO_ACCOUNT_SID;
    const authToken = process.env.TWILIO_AUTH_TOKEN;
    const fromNumber = process.env.TWILIO_FROM_NUMBER;
    if (!accountSid || !authToken || !fromNumber) {
      throw new Error('Twilio environment variables are required');
    }

    const heading = taskTitle
      ? `New Peezy support message — ${taskTitle}`
      : 'New Peezy support message';
    let body = `💬 ${heading}\nUser: ${uid}\n\n${textPreview}`;
    if (body.length > 1500) {
      body = `${body.slice(0, 1497)}...`;
    }

    const client = twilio(accountSid, authToken, { timeout: SMS_TIMEOUT_MS }); // C5: provider timeout ≤ 300 s
    // C6.2: the send runs under a support_sms outbound lease keyed by the sender's root.
    await withOutboundLease(deps, { uid, channel: 'support_sms' }, () => client.messages.create({
      body,
      from: fromNumber,
      to: destination
    }));
  } catch (error) {
    logger.warn('SUPPORT_SMS_FAILED');
  }
}

/** `deps` is the lease dependency pair `{db, now}` (C3 outbound leases; millisecond clock). */
async function notifySupport(params, deps) {
  await Promise.all([
    sendEmail(params, deps),
    sendSms(params, deps)
  ]);
}

module.exports = { notifySupport };
