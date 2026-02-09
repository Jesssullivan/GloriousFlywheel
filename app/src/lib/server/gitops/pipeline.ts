import {
  readFile,
  createBranch,
  commitFile,
  createMergeRequest,
} from "./repository";
import { parseTfVars, serializeTfVars, applyChanges } from "./tfvars-parser";
import { computeDiff, unifiedDiff } from "./diff";
import { getTfvarsPath, getDefaultEnvironment } from "./config";
import type { ConfigDiff } from "$lib/types";
import type { Environment } from "$lib/types/environment";

// Default tfvars path (can be overridden via function parameters)
function getDefaultTfvarsPath(): string {
  return getTfvarsPath(getDefaultEnvironment());
}

const MR_TITLE_MAX = 255;
const MR_TITLE_PREFIX = "Update runner config: ";

/**
 * Build an MR title that fits within GitLab's 255-char limit.
 * Lists changed keys when they fit; falls back to a count summary.
 */
export function buildMrTitle(diffs: ConfigDiff[]): string {
  if (diffs.length === 0) return "Update runner configuration";

  const keys = diffs.map((d) => d.key).join(", ");
  const full = `${MR_TITLE_PREFIX}${keys}`;

  if (full.length <= MR_TITLE_MAX) return full;

  return `${MR_TITLE_PREFIX}${diffs.length} settings`;
}

export interface ChangeRequest {
  changes: Record<string, string | number | boolean>;
  description: string;
}

export interface ChangeResult {
  branch: string;
  mr_url: string;
  mr_iid: number;
  diffs: ConfigDiff[];
  unified_diff: string;
}

/**
 * Read the current tfvars from the repo and return parsed values.
 */
export async function getCurrentConfig(
  ref: string = "main",
  environment?: Environment | string
) {
  const tfvarsPath = environment ? getTfvarsPath(environment) : getDefaultTfvarsPath();
  const content = await readFile(tfvarsPath, ref);
  return parseTfVars(content);
}

/**
 * Full GitOps flow: read current config, apply changes, create branch + MR.
 */
export async function submitChanges(
  request: ChangeRequest,
  environment?: Environment | string
): Promise<ChangeResult> {
  const tfvarsPath = environment ? getTfvarsPath(environment) : getDefaultTfvarsPath();

  // 1. Read current config
  const currentContent = await readFile(tfvarsPath);
  const currentDoc = parseTfVars(currentContent);

  // 2. Apply changes
  const newDoc = applyChanges(currentDoc, request.changes);
  const newContent = serializeTfVars(newDoc);

  // 3. Compute diffs
  const diffs = computeDiff(currentDoc, newDoc);
  const diff = unifiedDiff(currentContent, newContent);

  // 4. Create branch
  const branch = `dashboard/runner-config-${Date.now()}`;
  await createBranch(branch);

  // 5. Commit changes
  const changedKeys = diffs.map((d) => d.key).join(", ");
  await commitFile(
    tfvarsPath,
    newContent,
    `feat(runners): update ${changedKeys}\n\n${request.description}`,
    branch,
  );

  // 6. Create MR (title must be <= 255 chars for GitLab API)
  const mrTitle = buildMrTitle(diffs);

  const mrDescription = [
    "## Runner Configuration Changes",
    "",
    "Updated via Runner Dashboard.",
    "",
    "### Changes",
    ...diffs.map(
      (d) =>
        `- **${d.key}**: ${d.old_value ?? "(none)"} -> ${d.new_value ?? "(removed)"}`,
    ),
    "",
    "### Diff",
    "```diff",
    diff,
    "```",
    "",
    request.description,
  ].join("\n");

  const mr = await createMergeRequest(
    branch,
    mrTitle,
    mrDescription,
  );

  return {
    branch,
    mr_url: mr.web_url,
    mr_iid: mr.iid,
    diffs,
    unified_diff: diff,
  };
}
