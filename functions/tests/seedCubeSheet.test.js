const assert = require("node:assert/strict");
const { test } = require("node:test");

const {
  buildConfigDocuments,
  cubeSheet,
  packingSim,
  seedCubeSheet,
  validateConfigDocuments
} = require("../seedCubeSheet");

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function documentsWith(mutate) {
  const cubeSheetData = clone(cubeSheet);
  const packingSimData = clone(packingSim);
  mutate({ cubeSheetData, packingSimData });
  return buildConfigDocuments({ cubeSheetData, packingSimData });
}

function noWriteAdmin() {
  let firestoreCalls = 0;
  return {
    client: {
      apps: [{}],
      firestore() {
        firestoreCalls += 1;
        throw new Error("Firestore must not be reached for an invalid fixture");
      }
    },
    get firestoreCalls() {
      return firestoreCalls;
    }
  };
}

test("the seeded Phase 1 configuration passes validation", () => {
  assert.doesNotThrow(() => validateConfigDocuments(buildConfigDocuments()));
  cubeSheet.rows.forEach((row) => {
    assert.ok(row.packingUnit?.behavior, `${row.key} must declare packingUnit.behavior`);
  });
  cubeSheet.rows.filter((row) => row.packProfile).forEach((row) => {
    assert.equal(typeof row.packProfile.protectionFactor, "number");
    assert.equal(typeof row.packProfile.compressionFactor, "number");
  });
});

test("broken fixtures fail loudly before any Firestore write", async (t) => {
  const fixtures = [
    {
      name: "schema",
      expectedError: /Schema validation failed/,
      mutate({ packingSimData }) {
        delete packingSimData.boxes;
      }
    },
    {
      name: "cross-reference",
      expectedError: /Cross-reference validation failed/,
      mutate({ cubeSheetData }) {
        cubeSheetData.rows.find((row) => row.key === "Books (each)").packProfile.lane = "missingLane";
      }
    },
    {
      name: "range",
      expectedError: /Range validation failed/,
      mutate({ packingSimData }) {
        packingSimData.lanes.dense.fillEfficiency += 1;
      }
    },
    {
      name: "boxability conflict",
      expectedError: /Conflict validation failed/,
      mutate({ cubeSheetData }) {
        const profile = cubeSheetData.rows.find((row) => row.key === "Books (each)").packProfile;
        delete profile.boxabilityPrecedence;
      }
    }
  ];

  for (const fixture of fixtures) {
    await t.test(fixture.name, async () => {
      const documents = documentsWith(fixture.mutate);
      const admin = noWriteAdmin();
      await assert.rejects(
        seedCubeSheet({ adminClient: admin.client, documents }),
        fixture.expectedError
      );
      assert.equal(admin.firestoreCalls, 0, "validation must finish before Firestore access");
    });
  }
});
