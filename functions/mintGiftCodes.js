const crypto = require('crypto');
const admin = require('firebase-admin');

const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const GIFT_TERM_MONTHS = 6;
const FIRESTORE_BATCH_LIMIT = 500;

function parseArguments(argv) {
  let count;
  let batchId;

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--count') {
      count = Number(argv[index + 1]);
      index += 1;
    } else if (argument === '--batch') {
      batchId = argv[index + 1];
      index += 1;
    } else {
      throw new Error(`Unknown argument: ${argument}`);
    }
  }

  if (!Number.isSafeInteger(count) || count < 1) {
    throw new Error('--count must be a positive integer');
  }
  if (typeof batchId !== 'string' || !batchId.trim()) {
    throw new Error('--batch must be a non-empty name');
  }

  return { count, batchId: batchId.trim() };
}

function randomSegment() {
  return Array.from({ length: 4 }, () => (
    CODE_ALPHABET[crypto.randomInt(CODE_ALPHABET.length)]
  )).join('');
}

function generateCode() {
  return `PEEZY-${randomSegment()}-${randomSegment()}`;
}

function generateUniqueCodes(count) {
  const codes = new Set();
  while (codes.size < count) {
    codes.add(generateCode());
  }
  return [...codes];
}

async function mintGiftCodes({ count, batchId }) {
  if (!admin.apps.length) {
    const serviceAccount = require('./serviceAccountKey.json');
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  }

  const db = admin.firestore();
  const codes = generateUniqueCodes(count);

  for (let offset = 0; offset < codes.length; offset += FIRESTORE_BATCH_LIMIT) {
    const batch = db.batch();
    for (const code of codes.slice(offset, offset + FIRESTORE_BATCH_LIMIT)) {
      batch.create(db.collection('giftCodes').doc(code), {
        status: 'unredeemed',
        batchId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        termMonths: GIFT_TERM_MONTHS
      });
    }
    await batch.commit();
  }

  return codes;
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  const codes = await mintGiftCodes(options);
  console.log(codes.join('\n'));
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}

module.exports = {
  generateCode,
  mintGiftCodes,
  parseArguments
};
