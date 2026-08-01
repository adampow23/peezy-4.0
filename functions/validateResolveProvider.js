const assert = require("assert/strict");
const Module = require("module");

// Keep the pure invariant harness independent of iCloud-resident deployment
// packages. Production dependency loading is validated by the deploy/runtime.
const originalLoad = Module._load;
Module._load = function loadResolverDependency(request, parent, isMain) {
  if (request === "firebase-functions/v2/https") {
    return {
      onCall: (_options, handler) => handler,
      HttpsError: class HttpsError extends Error {}
    };
  }
  if (request === "firebase-admin") {
    return {
      firestore: Object.assign(
        () => { throw new Error("Firestore must be dependency-injected in this harness"); },
        { FieldValue: { serverTimestamp: () => "SERVER_TIMESTAMP" } }
      )
    };
  }
  if (request === "@anthropic-ai/sdk") {
    return class Anthropic {};
  }
  return originalLoad(request, parent, isMain);
};
const { _test } = require("./resolveProvider");
Module._load = originalLoad;

async function run() {
  const addressURL = "https://provider.example/account/address";
  const cancelURL = "https://provider.example/account/cancel";
  const transferURL = "https://provider.example/account/transfer";
  const policyURL = "https://provider.example/policy";
  const citations = [
    { url: addressURL, title: "Official address help" },
    { url: cancelURL, title: "Official cancellation help" },
    { url: transferURL, title: "Official transfer help" },
    { url: policyURL, title: "Official policy" }
  ];

  const sameGym = {
    providerId: "example-gym",
    name: "Example Gym",
    aliases: ["Example Fitness"],
    category: "gym",
    addressChangeURL: addressURL,
    cancellationURL: cancelURL,
    transferLocationURL: transferURL,
    method: "link",
    citations
  };
  const cancellation = await _test.resolveProviderRequest("Example Gym", "membership", "cancel", {
    lookup: async (_name, _category, intent) => {
      assert.equal(intent, "cancel");
      return sameGym;
    },
    search: async () => assert.fail("Intent-compatible seed must not invoke search"),
    cache: async () => assert.fail("Intent-compatible seed must not write through")
  });
  const addressUpdate = await _test.resolveProviderRequest("Example Gym", "membership", "updateAddress", {
    lookup: async (_name, _category, intent) => {
      assert.equal(intent, "updateAddress");
      return sameGym;
    },
    search: async () => assert.fail("Intent-compatible seed must not invoke search"),
    cache: async () => assert.fail("Intent-compatible seed must not write through")
  });
  assert.equal(cancellation.url, cancelURL);
  assert.equal(addressUpdate.url, addressURL);
  assert.notEqual(cancellation.url, addressUpdate.url, "Same-company intents must return distinct paths");
  assert.equal(_test.directoryRecordPayload(sameGym, "Example Gym", "transferLocation").url, transferURL);
  assert.equal(_test.providerSupportsIntent(sameGym, "cancel"), true);
  assert.equal(_test.providerSupportsIntent({ ...sameGym, intent: "cancel" }, "updateAddress"), false);
  assert.equal(
    _test.providerSupportsIntent({ ...sameGym, source: "resolved" }, "cancel"),
    false,
    "Legacy company-only resolver cache rows must not satisfy an intent request"
  );

  assert.equal(_test.categoryFamily("brokerage investment"), "financial");
  assert.equal(_test.categoryFamily("auto insurance"), "insurance");
  assert.equal(_test.categoryFamily("yoga studio"), "membership");
  assert.notEqual(_test.categoryFamily("veterinarian"), _test.categoryFamily("insurance"));
  assert.equal(_test.providerMatchesCategory({ category: "subscription" }, "streaming"), true);
  assert.equal(_test.providerMatchesCategory({ category: "subscription" }, "membership"), false);

  const poisonedSeed = _test.directoryRecordPayload({
    providerId: "poisoned",
    name: "Poisoned",
    addressChangeURL: "https://attacker.example/invented",
    method: "link",
    citations
  }, "Poisoned", "updateAddress");
  assert.equal(poisonedSeed.method, "concierge");
  assert.ok(!Object.hasOwn(poisonedSeed, "url"));

  const validRequirement = {
    kind: "noticePeriod",
    text: "Give 30 days' notice.",
    noticeDays: 30,
    citationUrl: policyURL
  };
  const citedPolicy = _test.safePayload({
    name: "Example Gym",
    url: cancelURL,
    method: "link",
    confidence: "high",
    citations,
    requirements: [validRequirement]
  }, "Example Gym");
  assert.deepEqual(citedPolicy.requirements, [validRequirement]);

  for (const unsafeRequirement of [
    { ...validRequirement, citationUrl: "https://attacker.example/policy" },
    { ...validRequirement, noticeDays: 0 },
    { ...validRequirement, kind: "inventedPolicy" }
  ]) {
    const unsafe = _test.safePayload({
      name: "Example Gym",
      url: cancelURL,
      method: "link",
      confidence: "high",
      citations,
      requirements: [unsafeRequirement]
    }, "Example Gym");
    assert.equal(unsafe.method, "concierge");
    assert.deepEqual(unsafe.requirements, []);
    assert.ok(!Object.hasOwn(unsafe, "url"));
  }

  let cached = null;
  const resolved = await _test.resolveProviderRequest("New Provider", "utility", "updateAddress", {
    lookup: async () => null,
    search: async (_name, _category, intent) => {
      assert.equal(intent, "updateAddress");
      return {
        name: "New Provider",
        url: addressURL,
        method: "link",
        confidence: "high",
        citations: [{ url: addressURL, title: "Official address help" }],
        requirements: []
      };
    },
    cache: async (payload, requestedName, category, intent) => {
      cached = _test.resolvedDocument(payload, requestedName, category, intent);
    }
  });
  assert.equal(resolved.url, addressURL);
  assert.equal(cached.addressChangeURL, addressURL);
  assert.equal(cached.intent, "updateAddress");
  assert.match(cached.providerId, /_updateAddress$/);
  const cancelDocument = _test.resolvedDocument(citedPolicy, "Example Gym", "membership", "cancel");
  const updateDocument = _test.resolvedDocument(
    { ...citedPolicy, url: addressURL },
    "Example Gym",
    "membership",
    "updateAddress"
  );
  assert.notEqual(cancelDocument.providerId, updateDocument.providerId, "Cache keys must include intent");
  assert.equal(cancelDocument.cancellationURL, cancelURL);
  assert.equal(updateDocument.addressChangeURL, addressURL);

  const inMemoryDirectory = [];
  let searchCount = 0;
  const cacheDependencies = {
    lookup: async (name, category, intent) => inMemoryDirectory.find((record) =>
      _test.normalize(record.name) === _test.normalize(name) &&
      _test.providerMatchesCategory(record, category) &&
      _test.providerSupportsIntent(record, intent)
    ) || null,
    search: async () => {
      searchCount += 1;
      return {
        name: "Cache Test Gym",
        url: cancelURL,
        method: "link",
        confidence: "high",
        citations: [{ url: cancelURL, title: "Official cancellation help" }],
        requirements: []
      };
    },
    cache: async (payload, requestedName, category, intent) => {
      inMemoryDirectory.push(_test.resolvedDocument(payload, requestedName, category, intent));
    }
  };
  const first = await _test.resolveProviderRequest("Cache Test Gym", "gym", "cancel", cacheDependencies);
  const second = await _test.resolveProviderRequest("Cache Test Gym", "gym", "cancel", cacheDependencies);
  assert.equal(first.url, cancelURL);
  assert.equal(second.url, cancelURL);
  assert.equal(searchCount, 1, "Second identical company+intent request must hit cache");

  for (const unsafeResult of [
    { name: "Uncited", url: "https://attacker.example/invented", method: "link", confidence: "high", citations },
    { name: "Medium", url: addressURL, method: "link", confidence: "medium", citations },
    { name: "Malformed", method: "unexpected", confidence: "high", citations: [] }
  ]) {
    let didCache = false;
    const result = await _test.resolveProviderRequest(unsafeResult.name, "financial", "updateAddress", {
      lookup: async () => null,
      search: async () => unsafeResult,
      cache: async () => { didCache = true; }
    });
    assert.equal(result.method, "concierge");
    assert.ok(!Object.hasOwn(result, "url"));
    assert.deepEqual(result.requirements, []);
    assert.equal(didCache, false);
  }

  const failure = await _test.resolveProviderRequest("Fake Brand 9QZ", "subscription", "cancel", {
    lookup: async () => null,
    search: async () => { throw new Error("simulated failure"); },
    cache: async () => assert.fail("Failures must not cache")
  });
  assert.equal(failure.method, "concierge");

  const timeout = await _test.resolveProviderRequest("Slow Provider", "financial", "updateAddress", {
    lookup: async () => null,
    search: async () => new Promise(() => {}),
    cache: async () => assert.fail("Timeouts must not cache"),
    timeoutMs: 5
  });
  assert.equal(timeout.method, "concierge");

  const uncitedCall = _test.safePayload({
    name: "Invented Phone",
    phone: "1-800-555-0199",
    method: "call",
    confidence: "high",
    citations: []
  }, "Invented Phone");
  assert.equal(uncitedCall.method, "concierge");

  const response = _test.parseSearchResponse({
    content: [{
      type: "text",
      text: JSON.stringify({
        name: "Cited Provider",
        url: cancelURL,
        method: "link",
        confidence: "high",
        requirements: [validRequirement]
      }),
      citations: [
        { type: "web_search_result_location", url: cancelURL, title: "Official action", cited_text: "Cancel online." },
        { type: "web_search_result_location", url: policyURL, title: "Official policy", cited_text: "30 days." }
      ]
    }]
  });
  assert.equal(response.url, cancelURL);
  assert.deepEqual(response.requirements, [validRequirement]);

  console.log("✅ resolveProvider intent, requirement, citation, and cache harness passed");
}

run().catch((error) => {
  console.error(`❌ resolveProvider validator failed: ${error.stack || error.message}`);
  process.exit(1);
});
