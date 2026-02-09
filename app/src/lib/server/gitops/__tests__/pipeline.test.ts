import { describe, it, expect, vi, beforeEach } from "vitest";
import type { ConfigDiff } from "$lib/types";

// Mock $env/dynamic/private
vi.mock("$env/dynamic/private", () => ({
  env: {
    RUNNER_STACK_NAME: "gitlab-runners",
    ATTIC_DEFAULT_ENV: "dev",
  },
}));

// Mock repository functions
const mockReadFile = vi.fn();
const mockCreateBranch = vi.fn();
const mockCommitFile = vi.fn();
const mockCreateMergeRequest = vi.fn();

vi.mock("../repository", () => ({
  readFile: (...args: unknown[]) => mockReadFile(...args),
  createBranch: (...args: unknown[]) => mockCreateBranch(...args),
  commitFile: (...args: unknown[]) => mockCommitFile(...args),
  createMergeRequest: (...args: unknown[]) => mockCreateMergeRequest(...args),
}));

import { buildMrTitle, submitChanges } from "../pipeline";

const SAMPLE_TFVARS = `hpa_cpu_target = 70
docker_concurrent_jobs = 8
deploy_nix_runner = true
nix_job_cpu_limit = "500m"`;

describe("buildMrTitle", () => {
  it("should return keys when title fits within 255 chars", () => {
    const diffs: ConfigDiff[] = [
      { key: "hpa_cpu_target", old_value: "70", new_value: "80", type: "changed" },
    ];
    expect(buildMrTitle(diffs)).toBe("Update runner config: hpa_cpu_target");
  });

  it("should return fallback for empty diffs", () => {
    expect(buildMrTitle([])).toBe("Update runner configuration");
  });

  it("should include multiple keys when they fit", () => {
    const diffs: ConfigDiff[] = [
      { key: "hpa_cpu_target", old_value: "70", new_value: "80", type: "changed" },
      { key: "docker_concurrent_jobs", old_value: "8", new_value: "12", type: "changed" },
    ];
    const title = buildMrTitle(diffs);
    expect(title).toBe("Update runner config: hpa_cpu_target, docker_concurrent_jobs");
    expect(title.length).toBeLessThanOrEqual(255);
  });

  it("should fall back to count when keys exceed 255 chars", () => {
    // Generate enough long keys to exceed 255 chars
    const diffs: ConfigDiff[] = Array.from({ length: 20 }, (_, i) => ({
      key: `very_long_runner_configuration_key_name_${i}`,
      old_value: "old",
      new_value: "new",
      type: "changed" as const,
    }));

    const title = buildMrTitle(diffs);
    expect(title).toBe("Update runner config: 20 settings");
    expect(title.length).toBeLessThanOrEqual(255);
  });

  it("should always produce titles within the 255-char limit", () => {
    // Worst case: many keys just barely over the limit
    for (let count = 1; count <= 50; count++) {
      const diffs: ConfigDiff[] = Array.from({ length: count }, (_, i) => ({
        key: `docker_job_memory_limit_setting_${i}`,
        old_value: "old",
        new_value: "new",
        type: "changed" as const,
      }));
      const title = buildMrTitle(diffs);
      expect(title.length).toBeLessThanOrEqual(255);
    }
  });
});

describe("submitChanges", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    mockReadFile.mockReset();
    mockCreateBranch.mockReset();
    mockCommitFile.mockReset();
    mockCreateMergeRequest.mockReset();
  });

  it("should execute the full GitOps flow", async () => {
    mockReadFile.mockResolvedValue(SAMPLE_TFVARS);
    mockCreateBranch.mockResolvedValue(undefined);
    mockCommitFile.mockResolvedValue(undefined);
    mockCreateMergeRequest.mockResolvedValue({
      iid: 42,
      web_url: "https://gitlab.com/test/project/-/merge_requests/42",
    });

    const result = await submitChanges({
      changes: { hpa_cpu_target: 80 },
      description: "Raise CPU target",
    });

    expect(result.mr_iid).toBe(42);
    expect(result.mr_url).toContain("merge_requests/42");
    expect(result.branch).toMatch(/^dashboard\/runner-config-\d+$/);
    expect(result.diffs).toHaveLength(1);
    expect(result.diffs[0].key).toBe("hpa_cpu_target");
    expect(result.diffs[0].old_value).toBe("70");
    expect(result.diffs[0].new_value).toBe("80");
    expect(result.unified_diff).toContain("-hpa_cpu_target = 70");
    expect(result.unified_diff).toContain("+hpa_cpu_target = 80");
  });

  it("should read from the correct tfvars path", async () => {
    mockReadFile.mockResolvedValue(SAMPLE_TFVARS);
    mockCreateBranch.mockResolvedValue(undefined);
    mockCommitFile.mockResolvedValue(undefined);
    mockCreateMergeRequest.mockResolvedValue({ iid: 1, web_url: "" });

    await submitChanges({
      changes: { hpa_cpu_target: 80 },
      description: "test",
    });

    expect(mockReadFile).toHaveBeenCalledWith(
      "tofu/stacks/gitlab-runners/dev.tfvars",
    );
  });

  it("should use environment override for tfvars path", async () => {
    mockReadFile.mockResolvedValue(SAMPLE_TFVARS);
    mockCreateBranch.mockResolvedValue(undefined);
    mockCommitFile.mockResolvedValue(undefined);
    mockCreateMergeRequest.mockResolvedValue({ iid: 1, web_url: "" });

    await submitChanges(
      { changes: { hpa_cpu_target: 80 }, description: "test" },
      "beehive",
    );

    expect(mockReadFile).toHaveBeenCalledWith(
      "tofu/stacks/gitlab-runners/beehive.tfvars",
    );
  });

  it("should create a timestamped branch", async () => {
    mockReadFile.mockResolvedValue(SAMPLE_TFVARS);
    mockCreateBranch.mockResolvedValue(undefined);
    mockCommitFile.mockResolvedValue(undefined);
    mockCreateMergeRequest.mockResolvedValue({ iid: 1, web_url: "" });

    await submitChanges({
      changes: { hpa_cpu_target: 80 },
      description: "test",
    });

    expect(mockCreateBranch).toHaveBeenCalledWith(
      expect.stringMatching(/^dashboard\/runner-config-\d+$/),
    );
  });

  it("should commit with conventional commit message", async () => {
    mockReadFile.mockResolvedValue(SAMPLE_TFVARS);
    mockCreateBranch.mockResolvedValue(undefined);
    mockCommitFile.mockResolvedValue(undefined);
    mockCreateMergeRequest.mockResolvedValue({ iid: 1, web_url: "" });

    await submitChanges({
      changes: { hpa_cpu_target: 80 },
      description: "Raise CPU target",
    });

    expect(mockCommitFile).toHaveBeenCalledWith(
      "tofu/stacks/gitlab-runners/dev.tfvars",
      expect.stringContaining("hpa_cpu_target = 80"),
      expect.stringContaining("feat(runners): update hpa_cpu_target"),
      expect.stringMatching(/^dashboard\/runner-config-\d+$/),
    );

    // Commit message should include description
    const commitMsg = mockCommitFile.mock.calls[0][2];
    expect(commitMsg).toContain("Raise CPU target");
  });

  it("should create MR with title within 255-char limit", async () => {
    mockReadFile.mockResolvedValue(SAMPLE_TFVARS);
    mockCreateBranch.mockResolvedValue(undefined);
    mockCommitFile.mockResolvedValue(undefined);
    mockCreateMergeRequest.mockResolvedValue({ iid: 1, web_url: "" });

    await submitChanges({
      changes: { hpa_cpu_target: 80, docker_concurrent_jobs: 12 },
      description: "test",
    });

    const mrTitle = mockCreateMergeRequest.mock.calls[0][1];
    expect(mrTitle.length).toBeLessThanOrEqual(255);
    expect(mrTitle).toContain("hpa_cpu_target");
    expect(mrTitle).toContain("docker_concurrent_jobs");
  });

  it("should include change details in MR description", async () => {
    mockReadFile.mockResolvedValue(SAMPLE_TFVARS);
    mockCreateBranch.mockResolvedValue(undefined);
    mockCommitFile.mockResolvedValue(undefined);
    mockCreateMergeRequest.mockResolvedValue({ iid: 1, web_url: "" });

    await submitChanges({
      changes: { hpa_cpu_target: 80 },
      description: "Raise CPU target",
    });

    const mrDescription = mockCreateMergeRequest.mock.calls[0][2];
    expect(mrDescription).toContain("## Runner Configuration Changes");
    expect(mrDescription).toContain("**hpa_cpu_target**: 70 -> 80");
    expect(mrDescription).toContain("```diff");
    expect(mrDescription).toContain("Raise CPU target");
  });

  it("should propagate readFile errors", async () => {
    mockReadFile.mockRejectedValue(new Error("GitLab API error: 404"));

    await expect(
      submitChanges({
        changes: { hpa_cpu_target: 80 },
        description: "test",
      }),
    ).rejects.toThrow("404");
  });

  it("should propagate createBranch errors", async () => {
    mockReadFile.mockResolvedValue(SAMPLE_TFVARS);
    mockCreateBranch.mockRejectedValue(new Error("Branch already exists"));

    await expect(
      submitChanges({
        changes: { hpa_cpu_target: 80 },
        description: "test",
      }),
    ).rejects.toThrow("Branch already exists");
  });

  it("should propagate createMergeRequest errors", async () => {
    mockReadFile.mockResolvedValue(SAMPLE_TFVARS);
    mockCreateBranch.mockResolvedValue(undefined);
    mockCommitFile.mockResolvedValue(undefined);
    mockCreateMergeRequest.mockRejectedValue(
      new Error('GitLab API error: 400 - {"message":{"title":["is too long"]}}'),
    );

    await expect(
      submitChanges({
        changes: { hpa_cpu_target: 80 },
        description: "test",
      }),
    ).rejects.toThrow("400");
  });
});
