"use strict";

/** S3 I11: independent oracle recomputing F (reference bytes) and N (archive bytes) over binding-shaped Documents; imports nothing from the script. */

function u8(text) { return Buffer.byteLength(String(text), "utf8"); }

function valueBytes(value, acc) {
  acc.V += 1;
  switch (value.valueType) {
    case "nullValue": case "booleanValue": return 1;
    case "integerValue": return 9;
    case "doubleValue": { const d = value.doubleValue; return Number.isNaN(d) || d === Infinity || d === -Infinity ? 1 : 9; }
    case "timestampValue": return 13;
    case "stringValue": return 1 + 4 + u8(value.stringValue);
    case "bytesValue": return 1 + 4 + Buffer.from(value.bytesValue || []).length;
    case "referenceValue": { const n = u8(value.referenceValue); acc.F += n; return 1 + 4 + n; }
    case "geoPointValue": return 17;
    case "arrayValue": return 1 + 4 + ((value.arrayValue && value.arrayValue.values) || []).reduce((s, v) => s + valueBytes(v, acc), 0);
    case "mapValue": return 1 + mapBytes((value.mapValue && value.mapValue.fields) || {}, acc);
    default: throw new Error(`oracle: unknown oneof ${value.valueType}`);
  }
}

function mapBytes(fields, acc) {
  const keys = Object.keys(fields);
  acc.K += keys.length;
  return 4 + keys.reduce((s, k) => s + 4 + u8(k) + valueBytes(fields[k], acc), 0);
}

function archiveBytes(document) {
  const acc = { K: 0, V: 0, F: 0 };
  const N = 5 + 1 + (4 + u8(document.name)) + 12 + 12 + mapBytes(document.fields || {}, acc);
  return { N, ...acc };
}

module.exports = { archiveBytes };
