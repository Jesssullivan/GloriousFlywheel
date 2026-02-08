import { describe, it, expect, vi } from "vitest";

// Mock $env/dynamic/private
vi.mock("$env/dynamic/private", () => ({
  env: {
    RUNNER_NAMESPACE: "gitlab-runners",
  },
}));

import { QUERIES, TIME_WINDOWS } from "../queries";

describe("QUERIES", () => {
  describe("totalJobs", () => {
    it("should return namespaced query without runner", () => {
      const q = QUERIES.totalJobs();
      expect(q).toContain('namespace="gitlab-runners"');
      expect(q).not.toContain("runner=");
    });

    it("should include runner filter when specified", () => {
      const q = QUERIES.totalJobs("runner-docker");
      expect(q).toContain('runner="runner-docker"');
    });
  });

  describe("successRate", () => {
    it("should use 1h default window", () => {
      const q = QUERIES.successRate();
      expect(q).toContain("[1h]");
    });

    it("should accept custom window", () => {
      const q = QUERIES.successRate("6h");
      expect(q).toContain("[6h]");
    });
  });

  describe("jobsPerMinute", () => {
    it("should multiply by 60 for per-minute rate", () => {
      const q = QUERIES.jobsPerMinute();
      expect(q).toContain("* 60");
      expect(q).toContain("[5m]");
    });

    it("should accept runner filter", () => {
      const q = QUERIES.jobsPerMinute("runner-docker");
      expect(q).toContain('runner="runner-docker"');
    });
  });

  describe("enrollment metrics", () => {
    it("should return quota usage query with resource param", () => {
      const q = QUERIES.quotaUsage("requests.cpu");
      expect(q).toContain('resource="requests.cpu"');
    });

    it("should return pending jobs query", () => {
      const q = QUERIES.pendingJobs();
      expect(q).toContain('state="pending"');
    });

    it("should return orphaned namespaces query", () => {
      const q = QUERIES.orphanedNamespaces();
      expect(q).toContain("ci-job-");
    });

    it("should return recorded success rate query", () => {
      const q = QUERIES.recordedSuccessRate("runner-nix");
      expect(q).toContain("org:runner_success_rate:rate1h");
      expect(q).toContain('runner="runner-nix"');
    });

    it("should return HPA utilization query", () => {
      const q = QUERIES.hpaUtilization();
      expect(q).toContain("org:runner_hpa_utilization");
    });
  });

  describe("hpaCurrentReplicas", () => {
    it("should filter by runner when specified", () => {
      const q = QUERIES.hpaCurrentReplicas("runner-docker");
      expect(q).toContain("runner-docker");
    });

    it("should return all HPA replicas without runner", () => {
      const q = QUERIES.hpaCurrentReplicas();
      expect(q).not.toContain("horizontalpodautoscaler=~");
    });
  });
});

describe("TIME_WINDOWS", () => {
  it("should have 4 preset windows", () => {
    expect(Object.keys(TIME_WINDOWS)).toHaveLength(4);
  });

  it("should have correct 1h config", () => {
    expect(TIME_WINDOWS["1h"]).toEqual({
      seconds: 3600,
      step: "30s",
      label: "1 Hour",
    });
  });

  it("should have 7d as longest window", () => {
    expect(TIME_WINDOWS["7d"].seconds).toBe(604800);
  });
});
