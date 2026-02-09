import { describe, it, expect, vi, beforeEach } from "vitest";

// Mock $env/dynamic/private
vi.mock("$env/dynamic/private", () => ({
  env: {
    GITLAB_URL: "https://gitlab.com",
    GITLAB_TOKEN: "test-token",
    GITLAB_PROJECT_ID: "12345",
  },
}));

// Mock the gitlab client
const mockRequest = vi.fn();
vi.mock("$lib/server/gitlab/client", () => ({
  gitlab: { request: (...args: unknown[]) => mockRequest(...args) },
}));

import { readFile, createBranch, commitFile, createMergeRequest } from "../repository";

describe("readFile", () => {
  beforeEach(() => {
    mockRequest.mockReset();
  });

  it("should decode base64 content", async () => {
    const encoded = Buffer.from("hpa_cpu_target = 70").toString("base64");
    mockRequest.mockResolvedValue({ content: encoded, encoding: "base64" });

    const result = await readFile("tofu/stacks/runners/dev.tfvars");

    expect(result).toBe("hpa_cpu_target = 70");
    expect(mockRequest).toHaveBeenCalledWith(
      "/projects/12345/repository/files/tofu%2Fstacks%2Frunners%2Fdev.tfvars",
      { params: { ref: "main" } },
    );
  });

  it("should return raw content for non-base64 encoding", async () => {
    mockRequest.mockResolvedValue({ content: "raw content", encoding: "text" });

    const result = await readFile("file.txt");
    expect(result).toBe("raw content");
  });

  it("should use custom ref", async () => {
    mockRequest.mockResolvedValue({ content: "", encoding: "text" });

    await readFile("file.txt", "feature-branch");

    expect(mockRequest).toHaveBeenCalledWith(
      expect.any(String),
      { params: { ref: "feature-branch" } },
    );
  });

  it("should encode file paths with slashes", async () => {
    mockRequest.mockResolvedValue({ content: "", encoding: "text" });

    await readFile("tofu/stacks/gitlab-runners/beehive.tfvars");

    expect(mockRequest).toHaveBeenCalledWith(
      "/projects/12345/repository/files/tofu%2Fstacks%2Fgitlab-runners%2Fbeehive.tfvars",
      expect.any(Object),
    );
  });
});

describe("createBranch", () => {
  beforeEach(() => {
    mockRequest.mockReset();
  });

  it("should create branch from main by default", async () => {
    mockRequest.mockResolvedValue({});

    await createBranch("dashboard/runner-config-123");

    expect(mockRequest).toHaveBeenCalledWith(
      "/projects/12345/repository/branches",
      {
        method: "POST",
        body: { branch: "dashboard/runner-config-123", ref: "main" },
      },
    );
  });

  it("should create branch from custom ref", async () => {
    mockRequest.mockResolvedValue({});

    await createBranch("feature/test", "develop");

    expect(mockRequest).toHaveBeenCalledWith(
      "/projects/12345/repository/branches",
      {
        method: "POST",
        body: { branch: "feature/test", ref: "develop" },
      },
    );
  });
});

describe("commitFile", () => {
  beforeEach(() => {
    mockRequest.mockReset();
  });

  it("should commit file with correct parameters", async () => {
    mockRequest.mockResolvedValue({});

    await commitFile(
      "tofu/stacks/runners/dev.tfvars",
      "hpa_cpu_target = 80",
      "feat(runners): update hpa_cpu_target",
      "dashboard/runner-config-123",
    );

    expect(mockRequest).toHaveBeenCalledWith(
      "/projects/12345/repository/files/tofu%2Fstacks%2Frunners%2Fdev.tfvars",
      {
        method: "PUT",
        body: {
          branch: "dashboard/runner-config-123",
          content: "hpa_cpu_target = 80",
          commit_message: "feat(runners): update hpa_cpu_target",
          encoding: "text",
        },
      },
    );
  });
});

describe("createMergeRequest", () => {
  beforeEach(() => {
    mockRequest.mockReset();
  });

  it("should create MR with correct parameters", async () => {
    mockRequest.mockResolvedValue({
      iid: 42,
      web_url: "https://gitlab.com/test/-/merge_requests/42",
    });

    const result = await createMergeRequest(
      "dashboard/runner-config-123",
      "Update runner config: hpa_cpu_target",
      "## Changes\n- hpa_cpu_target: 70 -> 80",
    );

    expect(result.iid).toBe(42);
    expect(result.web_url).toContain("merge_requests/42");
    expect(mockRequest).toHaveBeenCalledWith(
      "/projects/12345/merge_requests",
      {
        method: "POST",
        body: {
          source_branch: "dashboard/runner-config-123",
          target_branch: "main",
          title: "Update runner config: hpa_cpu_target",
          description: "## Changes\n- hpa_cpu_target: 70 -> 80",
          squash: true,
          remove_source_branch: true,
        },
      },
    );
  });

  it("should use custom target branch", async () => {
    mockRequest.mockResolvedValue({ iid: 1, web_url: "" });

    await createMergeRequest("feature/test", "Title", "Desc", "develop");

    expect(mockRequest).toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({
        body: expect.objectContaining({
          target_branch: "develop",
        }),
      }),
    );
  });

  it("should set squash and remove_source_branch", async () => {
    mockRequest.mockResolvedValue({ iid: 1, web_url: "" });

    await createMergeRequest("branch", "Title", "Desc");

    const body = mockRequest.mock.calls[0][1].body;
    expect(body.squash).toBe(true);
    expect(body.remove_source_branch).toBe(true);
  });
});
