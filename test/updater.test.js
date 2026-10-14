import assert from "node:assert/strict";
import test from "node:test";
import { spawnSync } from "node:child_process";

test("update packaging rejects invalid feeds, keys, and release metadata", () => {
  const result = spawnSync("python3", ["-B", "-m", "unittest", "discover", "-s", "test", "-p", "updater_checks.py"], { encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr || result.stdout);
});
