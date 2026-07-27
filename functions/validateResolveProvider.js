const assert = require("assert/strict");
const { _test } = require("./resolveProvider");

async function run() {
  const officialURL = "https://provider.example/account/address";
  const citation = { url: officialURL, title: "Official address help" };

  const seeded = await _test.resolveProviderRequest("Example Alias", "financial", {
    lookup: async () => ({
      providerId: "example",
      name: "Example Provider",
      aliases: ["Example Alias"],
      addressChangeURL: officialURL,
      method: "link",
      citations: [citation]
    }),
    search: async () => assert.fail("Seeded aliases must not invoke search"),
    cache: async () => assert.fail("Seeded aliases must not write through")
  });
  assert.equal(seeded.url, officialURL);
  assert.equal(seeded.citations[0].url, officialURL);

  const poisonedSeed = _test.directoryRecordPayload({
    providerId: "poisoned",
    name: "Poisoned",
    addressChangeURL: "https://attacker.example/invented",
    method: "link",
    citations: [citation]
  }, "Poisoned");
  assert.equal(poisonedSeed.method, "concierge");
  assert.ok(!Object.hasOwn(poisonedSeed, "url"));

  let cached = null;
  const resolved = await _test.resolveProviderRequest("New Provider", "utility", {
    lookup: async () => null,
    search: async () => ({
      name: "New Provider",
      url: officialURL,
      method: "link",
      confidence: "high",
      citations: [citation]
    }),
    cache: async (payload) => { cached = payload; }
  });
  assert.equal(resolved.url, officialURL);
  assert.equal(cached.url, officialURL);

  for (const unsafeResult of [
    { name: "Uncited", url: "https://attacker.example/invented", method: "link", confidence: "high", citations: [citation] },
    { name: "Medium", url: officialURL, method: "link", confidence: "medium", citations: [citation] },
    { name: "Malformed", method: "unexpected", confidence: "high", citations: [] }
  ]) {
    let didCache = false;
    const result = await _test.resolveProviderRequest(unsafeResult.name, "financial", {
      lookup: async () => null,
      search: async () => unsafeResult,
      cache: async () => { didCache = true; }
    });
    assert.equal(result.method, "concierge");
    assert.ok(!Object.hasOwn(result, "url"));
    assert.equal(didCache, false);
  }

  const failure = await _test.resolveProviderRequest("Fake Brand 9QZ", "subscription", {
    lookup: async () => null,
    search: async () => { throw new Error("simulated failure"); },
    cache: async () => assert.fail("Failures must not cache")
  });
  assert.equal(failure.method, "concierge");
  assert.ok(!Object.hasOwn(failure, "url"));

  const response = _test.parseSearchResponse({
    content: [{
      type: "text",
      text: JSON.stringify({ name: "Cited Provider", url: officialURL, method: "link", confidence: "high" }),
      citations: [{
        type: "web_search_result_location",
        url: officialURL,
        title: "Official address help",
        cited_text: "Update your address online."
      }]
    }]
  });
  assert.equal(response.url, officialURL);
  assert.equal(response.citations[0].url, response.url);

  console.log("✅ resolveProvider invariant harness passed");
}

run().catch((error) => {
  console.error(`❌ resolveProvider validator failed: ${error.stack || error.message}`);
  process.exit(1);
});
