import { describe, it, expect, vi, beforeEach } from "vitest";
import { GitLabAPIError, GitLabClient } from "../client";

// Mock $env/dynamic/private
vi.mock("$env/dynamic/private", () => ({
  env: {
    GITLAB_URL: "https://gitlab.com",
    GITLAB_TOKEN: "test-token",
  },
}));

describe("GitLabAPIError", () => {
  it("should store status and message", () => {
    const err = new GitLabAPIError(404, "Not found");
    expect(err.status).toBe(404);
    expect(err.message).toBe("Not found");
    expect(err.name).toBe("GitLabAPIError");
  });

  it("should store optional body", () => {
    const err = new GitLabAPIError(500, "Server error", { detail: "oops" });
    expect(err.body).toEqual({ detail: "oops" });
  });
});

describe("GitLabClient", () => {
  let client: GitLabClient;

  beforeEach(() => {
    client = new GitLabClient("https://gitlab.com", "test-token");
    vi.restoreAllMocks();
  });

  it("should construct with base URL and token", () => {
    // Verify it creates a working client (no throw)
    expect(client).toBeInstanceOf(GitLabClient);
  });

  it("should throw GitLabAPIError on non-OK response", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response("Not found", { status: 404 }),
    );

    await expect(client.request("/projects/123")).rejects.toThrow(
      GitLabAPIError,
    );
  });

  it("should throw rate limit error on 429", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response("Rate limited", { status: 429 }),
    );

    await expect(client.request("/projects")).rejects.toThrow(
      "Rate limited by GitLab API",
    );
  });

  it("should return parsed JSON on success", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ id: 1, name: "test" }), { status: 200 }),
    );

    const result = await client.request<{ id: number; name: string }>(
      "/projects/1",
    );
    expect(result).toEqual({ id: 1, name: "test" });
  });

  it("should return undefined for 204 responses", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(null, { status: 204 }),
    );

    const result = await client.request("/projects/1/runners/5");
    expect(result).toBeUndefined();
  });

  it("should include PRIVATE-TOKEN header", async () => {
    const fetchSpy = vi
      .spyOn(globalThis, "fetch")
      .mockResolvedValue(new Response("[]", { status: 200 }));

    await client.request("/groups");
    expect(fetchSpy).toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({
        headers: expect.objectContaining({
          "PRIVATE-TOKEN": "test-token",
        }),
      }),
    );
  });

  it("should create new client with withToken", () => {
    const newClient = client.withToken("new-token");
    expect(newClient).toBeInstanceOf(GitLabClient);
    expect(newClient).not.toBe(client);
  });
});
