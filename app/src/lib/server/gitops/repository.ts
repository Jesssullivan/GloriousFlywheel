import { gitlab } from "$lib/server/gitlab/client";
import { env } from '$env/dynamic/private';

const PROJECT_ID = env.GITLAB_PROJECT_ID ?? '';

/**
 * Read a file from the GitLab repository.
 */
export async function readFile(
  path: string,
  ref: string = "main",
): Promise<string> {
  const encodedPath = encodeURIComponent(path);
  const response = await gitlab.request<{ content: string; encoding: string }>(
    `/projects/${PROJECT_ID}/repository/files/${encodedPath}`,
    { params: { ref } },
  );

  if (response.encoding === "base64") {
    return Buffer.from(response.content, "base64").toString("utf-8");
  }
  return response.content;
}

/**
 * Create a new branch from a source branch.
 */
export async function createBranch(
  branchName: string,
  ref: string = "main",
): Promise<void> {
  await gitlab.request(`/projects/${PROJECT_ID}/repository/branches`, {
    method: "POST",
    body: { branch: branchName, ref },
  });
}

/**
 * Commit a file change to a branch.
 */
export async function commitFile(
  path: string,
  content: string,
  message: string,
  branch: string,
): Promise<void> {
  const encodedPath = encodeURIComponent(path);
  await gitlab.request(
    `/projects/${PROJECT_ID}/repository/files/${encodedPath}`,
    {
      method: "PUT",
      body: {
        branch,
        content,
        commit_message: message,
        encoding: "text",
      },
    },
  );
}

/**
 * Create a merge request.
 */
export async function createMergeRequest(
  sourceBranch: string,
  title: string,
  description: string,
  targetBranch: string = "main",
): Promise<{ iid: number; web_url: string }> {
  return gitlab.request(`/projects/${PROJECT_ID}/merge_requests`, {
    method: "POST",
    body: {
      source_branch: sourceBranch,
      target_branch: targetBranch,
      title,
      description,
      squash: true,
      remove_source_branch: true,
    },
  });
}
