/**
 * Best-effort founder notifications for new support messages.
 * Each channel is enabled only when its SUPPORT_NOTIFY_* destination is set.
 */

const nodemailer = require('nodemailer');
const twilio = require('twilio');

const SUPPORT_FROM_EMAIL = 'adam@peezymove.com';

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
        user: SUPPORT_FROM_EMAIL,
        pass: appPassword
      }
    });
  }
  return transporter;
}

async function sendEmail({ uid, textPreview, taskTitle }) {
  const destination = process.env.SUPPORT_NOTIFY_EMAIL;
  if (!destination) return;

  try {
    const subject = taskTitle
      ? `New Peezy support message — ${taskTitle}`
      : 'New Peezy support message';
    const taskLine = taskTitle ? `Task: ${taskTitle}\n` : '';

    await getTransporter().sendMail({
      from: `"Peezy Move" <${SUPPORT_FROM_EMAIL}>`,
      to: destination,
      subject,
      text: `User: ${uid}\n${taskLine}\n${textPreview}`
    });
  } catch (error) {
    console.error('[notifySupport] Email failed:', error.message);
  }
}

async function sendSms({ uid, textPreview, taskTitle }) {
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

    const client = twilio(accountSid, authToken);
    await client.messages.create({
      body,
      from: fromNumber,
      to: destination
    });
  } catch (error) {
    console.error('[notifySupport] SMS failed:', error.message);
  }
}

async function notifySupport(params) {
  await Promise.all([
    sendEmail(params),
    sendSms(params)
  ]);
}

module.exports = { notifySupport };
