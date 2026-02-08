import { describe, it, expect } from "vitest";
import { computeDiff, unifiedDiff } from "../diff";
import { parseTfVars, applyChanges } from "../tfvars-parser";

const SAMPLE = `hpa_cpu_target = 70
docker_concurrent_jobs = 8
deploy_nix_runner = true`;

describe("computeDiff", () => {
  it("should detect changed values", () => {
    const before = parseTfVars(SAMPLE);
    const after = applyChanges(before, { hpa_cpu_target: 80 });
    const diffs = computeDiff(before, after);

    expect(diffs).toHaveLength(1);
    expect(diffs[0]).toEqual({
      key: "hpa_cpu_target",
      old_value: "70",
      new_value: "80",
      type: "changed",
    });
  });

  it("should detect multiple changes", () => {
    const before = parseTfVars(SAMPLE);
    const after = applyChanges(before, {
      hpa_cpu_target: 80,
      docker_concurrent_jobs: 12,
    });
    const diffs = computeDiff(before, after);

    expect(diffs).toHaveLength(2);
    const keys = diffs.map((d) => d.key);
    expect(keys).toContain("hpa_cpu_target");
    expect(keys).toContain("docker_concurrent_jobs");
  });

  it("should return empty for identical documents", () => {
    const before = parseTfVars(SAMPLE);
    const after = parseTfVars(SAMPLE);
    const diffs = computeDiff(before, after);
    expect(diffs).toHaveLength(0);
  });
});

describe("unifiedDiff", () => {
  it("should generate diff header", () => {
    const result = unifiedDiff("a = 1", "a = 2");
    expect(result).toContain("--- a/dev.tfvars");
    expect(result).toContain("+++ b/dev.tfvars");
  });

  it("should show additions and removals", () => {
    const result = unifiedDiff("a = 1", "a = 2");
    expect(result).toContain("-a = 1");
    expect(result).toContain("+a = 2");
  });
});
