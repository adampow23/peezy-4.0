/**
 * JoinWaitlistTest.js
 *
 * Isolated, read-only verification of functions/joinWaitlist.js.
 * Tests the pure helper logic (email validation + doc-id escaping + rate limiting)
 * against real inputs — NO Firebase connection, NO live SMTP, NO production mutation.
 *
 * Run from repo root:
 *     node Tests/JoinWaitlistTest.js
 *
 * Per Peezy testing methodology: this file READS from the real production source
 * using regex extraction (not re-imports) so it fails loudly if production code
 * drifts away from the tested invariants. It never injects mocks into production
 * files, and it can be deleted at any time without touching production.
 */

const fs = require('fs');
const path = require('path');

// ─────────────────────────────────────────────
// Load the real production file as text, extract
// the pure helpers, and eval them in isolation.
// ─────────────────────────────────────────────

const PROD_PATH = path.join(__dirname, '..', 'functions', 'joinWaitlist.js');
const src = fs.readFileSync(PROD_PATH, 'utf8');

// Extract each pure helper by name using a brace-balancing slice.
function extractFunction(source, name) {
  const marker = `function ${name}(`;
  const start = source.indexOf(marker);
  if (start === -1) throw new Error(`Could not find function ${name} in ${PROD_PATH}`);
  // Walk forward to the first '{' then match balanced braces.
  let i = source.indexOf('{', start);
  if (i === -1) throw new Error(`No opening brace for ${name}`);
  let depth = 0;
  for (; i < source.length; i++) {
    if (source[i] === '{') depth++;
    else if (source[i] === '}') {
      depth--;
      if (depth === 0) {
        return source.slice(start, i + 1);
      }
    }
  }
  throw new Error(`Unbalanced braces for ${name}`);
}

// Also pull out the regex + constants so the test uses the EXACT same values as prod.
function extractConst(source, name) {
  const re = new RegExp(`const\\s+${name}\\s*=\\s*([^;]+);`);
  const m = source.match(re);
  if (!m) throw new Error(`Could not find const ${name} in ${PROD_PATH}`);
  return m[1].trim();
}

// Build an isolated scope with the same constants + helpers as production
const sandbox = `
  const EMAIL_REGEX = ${extractConst(src, 'EMAIL_REGEX')};
  const MAX_EMAIL_LENGTH = ${extractConst(src, 'MAX_EMAIL_LENGTH')};
  const RATE_LIMIT_WINDOW_MS = ${extractConst(src, 'RATE_LIMIT_WINDOW_MS')};
  const RATE_LIMIT_MAX = ${extractConst(src, 'RATE_LIMIT_MAX')};
  const rateLimitMap = new Map();
  ${extractFunction(src, 'normalizeEmail')}
  ${extractFunction(src, 'emailToDocId')}
  ${extractFunction(src, 'checkRateLimit')}
  return { normalizeEmail, emailToDocId, checkRateLimit, EMAIL_REGEX, MAX_EMAIL_LENGTH, RATE_LIMIT_MAX };
`;

// eslint-disable-next-line no-new-func
const helpers = new Function(sandbox)();

// ─────────────────────────────────────────────
// Test runner
// ─────────────────────────────────────────────

let passed = 0;
let failed = 0;
const failures = [];

function t(name, fn) {
  try {
    fn();
    passed++;
    console.log(`  ✓ ${name}`);
  } catch (err) {
    failed++;
    failures.push({ name, err });
    console.log(`  ✗ ${name}\n      ${err.message}`);
  }
}

function eq(actual, expected, label) {
  if (actual !== expected) {
    throw new Error(`${label || 'mismatch'}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

function truthy(v, label) {
  if (!v) throw new Error(`${label || 'expected truthy'}: got ${JSON.stringify(v)}`);
}

function falsy(v, label) {
  if (v) throw new Error(`${label || 'expected falsy'}: got ${JSON.stringify(v)}`);
}

// ─────────────────────────────────────────────
// Suites
// ─────────────────────────────────────────────

console.log('\nnormalizeEmail()');
t('accepts plain email', () => eq(helpers.normalizeEmail('adam@peezymove.com'), 'adam@peezymove.com'));
t('lowercases', () => eq(helpers.normalizeEmail('Adam@Peezymove.COM'), 'adam@peezymove.com'));
t('trims whitespace', () => eq(helpers.normalizeEmail('   adam@peezymove.com  '), 'adam@peezymove.com'));
t('trims + lowercases combined', () => eq(helpers.normalizeEmail('  ADAM@peezyMove.com  '), 'adam@peezymove.com'));
t('accepts plus-addressing', () => eq(helpers.normalizeEmail('adam+waitlist@peezymove.com'), 'adam+waitlist@peezymove.com'));
t('accepts subdomain', () => eq(helpers.normalizeEmail('a@mail.peezymove.com'), 'a@mail.peezymove.com'));
t('rejects empty string', () => eq(helpers.normalizeEmail(''), null));
t('rejects whitespace only', () => eq(helpers.normalizeEmail('   '), null));
t('rejects missing @', () => eq(helpers.normalizeEmail('adampeezymove.com'), null));
t('rejects missing domain', () => eq(helpers.normalizeEmail('adam@'), null));
t('rejects missing TLD', () => eq(helpers.normalizeEmail('adam@peezymove'), null));
t('rejects non-string input (number)', () => eq(helpers.normalizeEmail(12345), null));
t('rejects non-string input (null)', () => eq(helpers.normalizeEmail(null), null));
t('rejects non-string input (undefined)', () => eq(helpers.normalizeEmail(undefined), null));
t('rejects non-string input (object)', () => eq(helpers.normalizeEmail({ email: 'x@y.z' }), null));
t('rejects email > MAX_EMAIL_LENGTH', () => {
  const giant = 'a'.repeat(250) + '@peezymove.com';
  eq(helpers.normalizeEmail(giant), null);
});
t('accepts email at exactly MAX_EMAIL_LENGTH', () => {
  const local = 'a'.repeat(helpers.MAX_EMAIL_LENGTH - '@peezymove.com'.length);
  const edge = local + '@peezymove.com';
  eq(edge.length, helpers.MAX_EMAIL_LENGTH, 'edge length sanity');
  eq(helpers.normalizeEmail(edge), edge);
});
t('rejects embedded whitespace', () => eq(helpers.normalizeEmail('adam @peezymove.com'), null));

console.log('\nemailToDocId()');
t('escapes dots to commas', () => eq(helpers.emailToDocId('adam@peezymove.com'), 'adam@peezymove,com'));
t('escapes multiple dots', () => eq(helpers.emailToDocId('a.b@sub.peezymove.com'), 'a,b@sub,peezymove,com'));
t('escapes slashes too', () => eq(helpers.emailToDocId('a/b@c.com'), 'a_b@c,com'));
t('is a valid Firestore doc id (no / or . or ..)', () => {
  const id = helpers.emailToDocId('a.b.c@peezymove.com');
  falsy(id.includes('/'), 'contains slash');
  falsy(id.includes('.'), 'contains dot');
  falsy(id === '..' || id === '.', 'reserved id');
  truthy(id.length > 0 && id.length <= 1500, 'length within Firestore limit');
});

console.log('\ncheckRateLimit()');
t('first N requests from same IP succeed', () => {
  const ip = '1.2.3.4';
  for (let i = 0; i < helpers.RATE_LIMIT_MAX; i++) {
    truthy(helpers.checkRateLimit(ip), `request ${i + 1} should succeed`);
  }
});
t('request N+1 from same IP is blocked', () => {
  falsy(helpers.checkRateLimit('1.2.3.4'), 'should be rate limited');
});
t('different IP is not affected', () => {
  truthy(helpers.checkRateLimit('9.9.9.9'), 'different IP should succeed');
});

// ─────────────────────────────────────────────
// Production-file invariants (read-verify, not re-test)
// ─────────────────────────────────────────────

console.log('\nProduction file invariants (read-only checks)');
t('joinWaitlist.js exists', () => truthy(fs.existsSync(PROD_PATH)));
t('declares GMAIL_APP_PASSWORD secret', () => truthy(/secrets:\s*\[\s*'GMAIL_APP_PASSWORD'/.test(src)));
t('uses cors: true', () => truthy(/cors:\s*true/.test(src)));
t('writes to waitlistSignups collection', () => truthy(/collection\(COLLECTION\)/.test(src) && /COLLECTION\s*=\s*'waitlistSignups'/.test(src)));
t('sends to ADMIN_NOTIFY_EMAIL = adampow23@gmail.com', () => truthy(/ADMIN_NOTIFY_EMAIL\s*=\s*'adampow23@gmail\.com'/.test(src)));
t('from address is adam@peezymove.com', () => truthy(/ADMIN_EMAIL\s*=\s*'adam@peezymove\.com'/.test(src)));
t('writes Firestore doc BEFORE sending email (no-lost-signup invariant)', () => {
  const writeIdx = src.indexOf('docRef.set(');
  const welcomeIdx = src.indexOf('sendMail');
  truthy(writeIdx !== -1 && welcomeIdx !== -1, 'both present');
  truthy(writeIdx < welcomeIdx, 'write must happen before sendMail');
});
t('dedupe check precedes write', () => {
  const existsIdx = src.indexOf('existing.exists');
  const writeIdx = src.indexOf('docRef.set(');
  truthy(existsIdx !== -1 && existsIdx < writeIdx, 'dedupe check must come first');
});
t('rejects non-POST methods', () => truthy(/req\.method\s*!==\s*'POST'/.test(src)));
t('index.js exports joinWaitlist', () => {
  const idx = fs.readFileSync(path.join(__dirname, '..', 'functions', 'index.js'), 'utf8');
  truthy(/exports\.joinWaitlist\s*=\s*joinWaitlist/.test(idx), 'missing export in index.js');
  truthy(/require\(['"]\.\/joinWaitlist['"]\)/.test(idx), 'missing require in index.js');
});
t('firestore.rules locks down waitlistSignups', () => {
  const rules = fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8');
  // Grab the waitlistSignups block and assert it denies all client access
  const blockMatch = rules.match(/match\s+\/waitlistSignups\/\{[^}]+\}\s*\{([\s\S]*?)\}/);
  truthy(blockMatch, 'waitlistSignups match block not found');
  const body = blockMatch[1];
  truthy(/allow\s+read,\s*write:\s*if\s+false/.test(body),
    'waitlistSignups should deny all client read/write');
});

// ─────────────────────────────────────────────
// Summary
// ─────────────────────────────────────────────

console.log(`\n${passed} passed, ${failed} failed`);
if (failed > 0) {
  console.log('\nFAILURES:');
  for (const f of failures) console.log(`  - ${f.name}: ${f.err.message}`);
  process.exit(1);
}
process.exit(0);
