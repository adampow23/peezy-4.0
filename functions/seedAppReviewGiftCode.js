/**
 * One-off seed for the App Review gift code.
 *
 * Run from functions/ with:
 *   node seedAppReviewGiftCode.js
 */

const admin = require('firebase-admin');

const serviceAccount = require('./serviceAccountKey.json');
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });

const db = admin.firestore();
const COLLECTION = 'giftCodes';
const GIFT_CODE_PATTERN = /^PEEZY-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$/;
const CODE = 'PEEZY-REVW-2626';
const LEGACY_CODE = 'GIVE-REVIEW1';

function printableData(data) {
  return Object.fromEntries(Object.entries(data).map(([key, value]) => [
    key,
    value instanceof admin.firestore.Timestamp ? value.toDate().toISOString() : value
  ]));
}

async function main() {
  const passesRegex = GIFT_CODE_PATTERN.test(CODE);
  if (!passesRegex) {
    throw new Error(`${CODE} does not match ${GIFT_CODE_PATTERN}`);
  }

  const codeRef = db.collection(COLLECTION).doc(CODE);
  const legacyCodeRef = db.collection(COLLECTION).doc(LEGACY_CODE);

  const batch = db.batch();
  batch.create(codeRef, {
    status: 'unredeemed',
    batchId: 'app-review',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    termMonths: 6
  });
  batch.delete(legacyCodeRef);
  await batch.commit();

  const [snapshot, legacySnapshot] = await Promise.all([
    codeRef.get(),
    legacyCodeRef.get()
  ]);
  console.log(JSON.stringify({
    code: CODE,
    regex: GIFT_CODE_PATTERN.toString(),
    passesRegex,
    document: {
      path: snapshot.ref.path,
      exists: snapshot.exists,
      data: printableData(snapshot.data())
    },
    deletedDocument: {
      path: legacySnapshot.ref.path,
      exists: legacySnapshot.exists
    }
  }, null, 2));
}

main()
  .catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  })
  .finally(() => admin.app().delete());
