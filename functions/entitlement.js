const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const { assertDeletionAbsent } = require('./accountDeletionFence');

const MOVE_PASS_PRODUCT_ID = 'peezy.plus.move';
const GIFT_CODE_SOURCE = 'giftCode';
const GIFT_TERM_MONTHS = 6;
const GIFT_CODE_PATTERN = /^PEEZY-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$/;

function parseExpirationDate(value) {
  let expirationDate;
  if (value instanceof Date) {
    expirationDate = value;
  } else if (typeof value?.toDate === 'function') {
    expirationDate = value.toDate();
  } else if (typeof value === 'string' || typeof value === 'number') {
    expirationDate = new Date(value);
  } else {
    return null;
  }

  return Number.isNaN(expirationDate.getTime()) ? null : expirationDate;
}

function addCalendarMonths(date, monthCount) {
  const result = new Date(date.getTime());
  const originalDay = result.getUTCDate();
  result.setUTCDate(1);
  result.setUTCMonth(result.getUTCMonth() + monthCount);

  const lastDayOfTargetMonth = new Date(Date.UTC(
    result.getUTCFullYear(),
    result.getUTCMonth() + 1,
    0
  )).getUTCDate();
  result.setUTCDate(Math.min(originalDay, lastDayOfTargetMonth));
  return result;
}

async function requireMovePass(uid) {
  const userSnapshot = await admin.firestore().collection('users').doc(uid).get();
  const expirationDate = parseExpirationDate(userSnapshot.data()?.subscription?.expirationDate);

  if (!expirationDate || expirationDate.getTime() <= Date.now()) {
    throw new HttpsError('permission-denied', 'Move Pass required', { reason: 'move-pass-required' });
  }
}

const redeemGiftCode = onCall(
  {
    region: 'us-central1',
    timeoutSeconds: 15,
    memory: '256MiB'
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be authenticated');
    }

    const code = typeof request.data?.code === 'string'
      ? request.data.code.trim().toUpperCase()
      : '';
    if (!code) {
      throw new HttpsError('invalid-argument', 'Gift code is required');
    }
    if (!GIFT_CODE_PATTERN.test(code)) {
      throw new HttpsError('not-found', "That code doesn't exist");
    }

    const db = admin.firestore();
    const giftCodeRef = db.collection('giftCodes').doc(code);
    const userRef = db.collection('users').doc(request.auth.uid);
    const now = new Date();
    const purchaseDate = now.toISOString();
    const expirationDate = addCalendarMonths(now, GIFT_TERM_MONTHS).toISOString();
    const serverTimestamp = admin.firestore.FieldValue.serverTimestamp();

    await db.runTransaction(async (transaction) => {
      const giftCodeSnapshot = await transaction.get(giftCodeRef);
      if (!giftCodeSnapshot.exists) {
        throw new HttpsError('not-found', "That code doesn't exist");
      }
      if (giftCodeSnapshot.data()?.status !== 'unredeemed') {
        throw new HttpsError('failed-precondition', 'This code was already used');
      }
      // C6.1 root fence: the committing transaction reads the owner root and requires accountDeletion absent.
      await assertDeletionAbsent(transaction, db, [request.auth.uid]);

      transaction.update(giftCodeRef, {
        status: 'redeemed',
        redeemedBy: request.auth.uid,
        redeemedAt: serverTimestamp
      });
      transaction.set(userRef, {
        subscription: {
          productId: MOVE_PASS_PRODUCT_ID,
          originalTransactionId: null,
          transactionId: null,
          purchaseDate,
          expirationDate,
          environment: null,
          isUpgraded: false,
          isActive: true,
          source: GIFT_CODE_SOURCE,
          updatedAt: serverTimestamp
        }
      }, { merge: true });
    });

    return { success: true, expirationDate };
  }
);

module.exports = {
  redeemGiftCode,
  requireMovePass
};
