import assert from "node:assert/strict";
import test from "node:test";

import { runInteraction } from "../../scripts/ci/browser-probe.mjs";

class FakeClient {
  constructor(results) {
    this.results = [...results];
    this.expressions = [];
  }

  async evaluate(expression) {
    this.expressions.push(expression);
    assert.ok(this.results.length > 0, "browser contract evaluated more expressions than expected");
    return this.results.shift();
  }
}

test("admin probe types, clicks, and waits for the reactive staged state", async () => {
  const client = new FakeClient([
    false,
    {
      ready: true,
      inputValue: "Firebat2 interaction proof",
      buttonText: "Stage local draft",
    },
    true,
  ]);
  const evidence = await runInteraction(client, "admin");
  assert.equal(evidence.action, "type-draft-and-click-stage-local-draft");
  assert.equal(evidence.assertedState, "Draft staged in this browser only — no command was sent");
  assert.match(client.expressions[1], /button\.click\(\)/);
});

test("public probe drives the filter while proving no admin controls", async () => {
  const client = new FakeClient([
    { ready: true, adminControlCount: 0, hasAdminText: false },
    true,
  ]);
  const evidence = await runInteraction(client, "public-site");
  assert.equal(evidence.action, "click-mathematics-filter");
  assert.equal(evidence.assertedState, "Selected: Mathematics");
  assert.equal(evidence.publicAdminControlCount, 0);
});

test("public probe fails closed when an admin control is visible", async () => {
  const client = new FakeClient([
    { ready: true, adminControlCount: 1, hasAdminText: false },
  ]);
  await assert.rejects(
    runInteraction(client, "public-site"),
    /public site exposed an administrative control or label/,
  );
});
