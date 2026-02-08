import type { TfVarsDocument } from "./tfvars-parser";
import type { ConfigDiff } from "$lib/types";

/**
 * Compute a structured diff between two tfvars documents.
 */
export function computeDiff(
  before: TfVarsDocument,
  after: TfVarsDocument,
): ConfigDiff[] {
  const diffs: ConfigDiff[] = [];
  const allKeys = new Set([
    ...Object.keys(before.values),
    ...Object.keys(after.values),
  ]);

  for (const key of allKeys) {
    const oldVal = before.values[key];
    const newVal = after.values[key];

    if (oldVal === undefined && newVal !== undefined) {
      diffs.push({
        key,
        old_value: undefined,
        new_value: String(newVal),
        type: "added",
      });
    } else if (oldVal !== undefined && newVal === undefined) {
      diffs.push({
        key,
        old_value: String(oldVal),
        new_value: undefined,
        type: "removed",
      });
    } else if (JSON.stringify(oldVal) !== JSON.stringify(newVal)) {
      diffs.push({
        key,
        old_value: String(oldVal),
        new_value: String(newVal),
        type: "changed",
      });
    }
  }

  return diffs.sort((a, b) => a.key.localeCompare(b.key));
}

/**
 * Generate a unified diff string for display.
 */
export function unifiedDiff(
  before: string,
  after: string,
  filename: string = "dev.tfvars",
): string {
  const oldLines = before.split("\n");
  const newLines = after.split("\n");
  const result: string[] = [`--- a/${filename}`, `+++ b/${filename}`];

  let i = 0;
  let j = 0;

  while (i < oldLines.length || j < newLines.length) {
    if (
      i < oldLines.length &&
      j < newLines.length &&
      oldLines[i] === newLines[j]
    ) {
      result.push(` ${oldLines[i]}`);
      i++;
      j++;
    } else if (
      i < oldLines.length &&
      (j >= newLines.length || oldLines[i] !== newLines[j])
    ) {
      result.push(`-${oldLines[i]}`);
      i++;
    } else {
      result.push(`+${newLines[j]}`);
      j++;
    }
  }

  return result.join("\n");
}
