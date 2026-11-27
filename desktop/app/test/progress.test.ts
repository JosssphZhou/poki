import assert from "node:assert/strict";
import test from "node:test";
import { failStep, type Step } from "../src/progress.ts";

test("a backend error without an active step is still a terminal failure", () => {
  const message = "Could not save the setup record.";
  const done: Step = { id: "install", title: "Installing", state: "done", notes: [] };
  for (const steps of [[], [done]]) {
    const result = failStep(steps, message);
    assert.deepEqual(result.slice(0, -1), steps);
    assert.equal(result.at(-1)?.state, "failed");
    assert.equal(result.at(-1)?.detail, message);
  }
});

test("a terminal error marks only the most recent active step", () => {
  const signing: Step = { id: "sign", title: "Signing", state: "active", notes: [] };
  const waiting: Step = { id: "close", title: "Checking", state: "waiting", notes: [], detail: "Please wait" };
  const result = failStep([signing, waiting], "Connection lost.");
  assert.deepEqual(result, [signing, { ...waiting, state: "failed", detail: "Connection lost." }]);
});
