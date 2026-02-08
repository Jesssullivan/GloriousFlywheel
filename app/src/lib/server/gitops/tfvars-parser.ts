/**
 * Conservative tfvars parser for the format used in environment tfvars files.
 * Handles: string, number, boolean, and simple map values.
 * Preserves comments, blank lines, and formatting for round-trip fidelity.
 */

export interface TfVarsLine {
  type:
    | "assignment"
    | "comment"
    | "blank"
    | "map-start"
    | "map-entry"
    | "map-end";
  raw: string;
  key?: string;
  value?: string | number | boolean | Record<string, string>;
}

export interface TfVarsDocument {
  lines: TfVarsLine[];
  values: Record<string, string | number | boolean | Record<string, string>>;
}

const ASSIGNMENT_RE = /^(\w+)\s*=\s*(.+)$/;
const MAP_START_RE = /^(\w+)\s*=\s*\{$/;
const MAP_ENTRY_RE = /^\s*"([^"]+)"\s*=\s*"([^"]+)"\s*$/;
const MAP_END_RE = /^\s*\}$/;

function parseValue(raw: string): string | number | boolean {
  const trimmed = raw.trim();

  // Boolean
  if (trimmed === "true") return true;
  if (trimmed === "false") return false;

  // Quoted string
  if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
    return trimmed.slice(1, -1);
  }

  // Number
  const num = Number(trimmed);
  if (!isNaN(num) && trimmed !== "") return num;

  // Strip inline comment and retry
  const commentIdx = trimmed.indexOf("#");
  if (commentIdx > 0) {
    return parseValue(trimmed.slice(0, commentIdx));
  }

  return trimmed;
}

export function parseTfVars(content: string): TfVarsDocument {
  const rawLines = content.split("\n");
  const lines: TfVarsLine[] = [];
  const values: Record<
    string,
    string | number | boolean | Record<string, string>
  > = {};

  let i = 0;
  while (i < rawLines.length) {
    const raw = rawLines[i];
    const trimmed = raw.trim();

    // Blank line
    if (trimmed === "") {
      lines.push({ type: "blank", raw });
      i++;
      continue;
    }

    // Comment line
    if (trimmed.startsWith("#")) {
      lines.push({ type: "comment", raw });
      i++;
      continue;
    }

    // Map start
    const mapMatch = MAP_START_RE.exec(trimmed);
    if (mapMatch) {
      const key = mapMatch[1];
      const mapValue: Record<string, string> = {};
      lines.push({ type: "map-start", raw, key });
      i++;

      while (i < rawLines.length) {
        const mapRaw = rawLines[i];
        const mapTrimmed = mapRaw.trim();

        if (MAP_END_RE.test(mapTrimmed)) {
          lines.push({ type: "map-end", raw: mapRaw, key });
          i++;
          break;
        }

        const entryMatch = MAP_ENTRY_RE.exec(mapTrimmed);
        if (entryMatch) {
          mapValue[entryMatch[1]] = entryMatch[2];
          lines.push({ type: "map-entry", raw: mapRaw, key });
        } else {
          // Comment or blank inside map
          lines.push({ type: "comment", raw: mapRaw });
        }
        i++;
      }

      values[key] = mapValue;
      continue;
    }

    // Simple assignment (may have inline comment)
    const assignMatch = ASSIGNMENT_RE.exec(trimmed);
    if (assignMatch) {
      const key = assignMatch[1];
      const value = parseValue(assignMatch[2]);
      lines.push({ type: "assignment", raw, key, value });
      values[key] = value;
      i++;
      continue;
    }

    // Unknown line - preserve as comment
    lines.push({ type: "comment", raw });
    i++;
  }

  return { lines, values };
}

function formatValue(
  value: string | number | boolean | Record<string, string>,
): string {
  if (typeof value === "boolean") return value ? "true" : "false";
  if (typeof value === "number") return value.toString();
  if (typeof value === "string") return `"${value}"`;
  return ""; // Maps handled separately
}

export function serializeTfVars(doc: TfVarsDocument): string {
  const result: string[] = [];

  for (const line of doc.lines) {
    if (line.type === "blank" || line.type === "comment") {
      result.push(line.raw);
    } else if (line.type === "assignment" && line.key) {
      // Preserve original alignment by replacing value in raw line
      const value = doc.values[line.key];
      if (value !== undefined && typeof value !== "object") {
        // Find position of the value in the raw line
        const eqIdx = line.raw.indexOf("=");
        const afterEq = line.raw.slice(eqIdx + 1);
        const commentIdx = findInlineComment(afterEq);
        const prefix = line.raw.slice(0, eqIdx + 1);

        if (commentIdx >= 0) {
          const comment = afterEq.slice(commentIdx);
          result.push(`${prefix} ${formatValue(value)} ${comment}`);
        } else {
          result.push(`${prefix} ${formatValue(value)}`);
        }
      } else {
        result.push(line.raw);
      }
    } else if (line.type === "map-start" && line.key) {
      result.push(line.raw);
    } else if (line.type === "map-entry") {
      result.push(line.raw);
    } else if (line.type === "map-end") {
      result.push(line.raw);
    } else {
      result.push(line.raw);
    }
  }

  return result.join("\n");
}

function findInlineComment(s: string): number {
  // Find # that's not inside a quoted string
  let inQuote = false;
  for (let i = 0; i < s.length; i++) {
    if (s[i] === '"') inQuote = !inQuote;
    if (s[i] === "#" && !inQuote) return i;
  }
  return -1;
}

/**
 * Apply a set of key-value changes to a parsed document.
 * Returns a new document with the updated values.
 */
export function applyChanges(
  doc: TfVarsDocument,
  changes: Record<string, string | number | boolean>,
): TfVarsDocument {
  const newValues = { ...doc.values, ...changes };
  return { lines: [...doc.lines], values: newValues };
}
