#!/usr/bin/env node

import { createHash } from "node:crypto";
import {
  existsSync,
  lstatSync,
  readFileSync,
  readdirSync,
  realpathSync,
} from "node:fs";
import { dirname, extname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import {
  defaultModuleManifestPath,
  inspectRegisteredProjects,
  loadModuleManifest,
} from "./logos-project.mjs";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
export const defaultRepositoryRoot = resolve(scriptDirectory, "..");
export const defaultPolicyPath = join(
  defaultRepositoryRoot,
  ".macsad",
  "policies",
  "logos-source-quality.json",
);

const debtEligibleRules = new Set([
  "duplicate-scoped-css",
  "scoped-css-preferred-length",
]);

function portable(path) {
  return path.split(sep).join("/");
}

function repositoryPath(root, path) {
  return portable(relative(root, path));
}

function compareLocations(left, right) {
  const leftMatch = left.match(/^(.*):([1-9][0-9]*)(?:-[1-9][0-9]*)?$/);
  const rightMatch = right.match(/^(.*):([1-9][0-9]*)(?:-[1-9][0-9]*)?$/);
  if (!leftMatch || !rightMatch) return left.localeCompare(right);
  const pathOrder = leftMatch[1].localeCompare(rightMatch[1]);
  return pathOrder || Number(leftMatch[2]) - Number(rightMatch[2]);
}

function digest(text) {
  return createHash("sha256").update(text, "utf8").digest("hex");
}

function exactKeys(value, expected, label) {
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  if (JSON.stringify(actual) !== JSON.stringify(wanted)) {
    throw new Error(`${label} must contain exactly: ${wanted.join(", ")}`);
  }
}

function exactInteger(value, minimum, maximum, label) {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    throw new Error(`${label} must be an integer from ${minimum} through ${maximum}`);
  }
  return value;
}

function loadJson(path, label) {
  let parsed;
  try {
    parsed = JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    throw new Error(`${label} cannot be read as JSON: ${error.message}`);
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error(`${label} must be one JSON object`);
  }
  return parsed;
}

export function loadSourcePolicy(path = defaultPolicyPath) {
  const policy = loadJson(path, "LOGOS source policy");
  exactKeys(
    policy,
    ["$schema", "schema", "files", "scopedCss", "duplicateBlocks", "markers", "debt"],
    "LOGOS source policy",
  );
  if (policy.schema !== "macsad-logos-source-quality/1") {
    throw new Error("LOGOS source policy has an unsupported schema");
  }
  if (policy.$schema !== "../schemas/logos-source-quality-v1.schema.json") {
    throw new Error("LOGOS source policy must reference the checked-in v1 JSON schema");
  }

  exactKeys(
    policy.files,
    ["maxPhysicalLines", "maxLogicalLinesPerDefinition", "maxLineLength"],
    "files policy",
  );
  exactInteger(policy.files.maxPhysicalLines, 20, 500, "files.maxPhysicalLines");
  exactInteger(
    policy.files.maxLogicalLinesPerDefinition,
    5,
    policy.files.maxPhysicalLines,
    "files.maxLogicalLinesPerDefinition",
  );
  exactInteger(policy.files.maxLineLength, 80, 300, "files.maxLineLength");

  exactKeys(
    policy.scopedCss,
    [
      "preferredMaxLineLength",
      "hardMaxLineLength",
      "duplicateMinimumDeclarations",
      "maximumIdenticalOccurrences",
    ],
    "scopedCss policy",
  );
  exactInteger(
    policy.scopedCss.preferredMaxLineLength,
    policy.files.maxLineLength,
    2000,
    "scopedCss.preferredMaxLineLength",
  );
  exactInteger(
    policy.scopedCss.hardMaxLineLength,
    policy.scopedCss.preferredMaxLineLength,
    8000,
    "scopedCss.hardMaxLineLength",
  );
  exactInteger(
    policy.scopedCss.duplicateMinimumDeclarations,
    4,
    50,
    "scopedCss.duplicateMinimumDeclarations",
  );
  if (policy.scopedCss.maximumIdenticalOccurrences !== 1) {
    throw new Error("scopedCss.maximumIdenticalOccurrences must be exactly 1");
  }

  exactKeys(
    policy.duplicateBlocks,
    ["minimumStatements", "minimumBehaviorStatements", "maximumOccurrences"],
    "duplicateBlocks policy",
  );
  exactInteger(
    policy.duplicateBlocks.minimumStatements,
    4,
    20,
    "duplicateBlocks.minimumStatements",
  );
  exactInteger(
    policy.duplicateBlocks.minimumBehaviorStatements,
    1,
    policy.duplicateBlocks.minimumStatements,
    "duplicateBlocks.minimumBehaviorStatements",
  );
  if (policy.duplicateBlocks.maximumOccurrences !== 1) {
    throw new Error("duplicateBlocks.maximumOccurrences must be exactly 1");
  }

  if (!Array.isArray(policy.markers) || policy.markers.length === 0) {
    throw new Error("markers must be a nonempty array");
  }
  const markerIds = new Set();
  for (const marker of policy.markers) {
    if (!marker || typeof marker !== "object" || Array.isArray(marker)) {
      throw new Error("each marker must be one object");
    }
    exactKeys(marker, ["id", "pattern", "flags"], "marker");
    if (typeof marker.id !== "string" || !/^[a-z][a-z0-9-]+$/.test(marker.id)) {
      throw new Error("each marker id must be stable lowercase kebab-case");
    }
    if (markerIds.has(marker.id)) throw new Error(`duplicate marker id: ${marker.id}`);
    markerIds.add(marker.id);
    if (typeof marker.pattern !== "string" || marker.pattern.length === 0) {
      throw new Error(`${marker.id} needs a nonempty pattern`);
    }
    if (typeof marker.flags !== "string" || !/^(?:i)?$/.test(marker.flags)) {
      throw new Error(`${marker.id} flags may be empty or exactly i`);
    }
    try {
      new RegExp(marker.pattern, marker.flags);
    } catch (error) {
      throw new Error(`${marker.id} has an invalid pattern: ${error.message}`);
    }
  }

  if (!Array.isArray(policy.debt)) throw new Error("debt must be an array");
  const debtIdentities = new Set();
  for (const entry of policy.debt) {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      throw new Error("each debt entry must be one object");
    }
    exactKeys(
      entry,
      ["rule", "fingerprint", "locations", "reason", "removalCondition"],
      "debt entry",
    );
    if (!debtEligibleRules.has(entry.rule)) {
      throw new Error(
        `debt cannot suppress ${String(entry.rule)}; only exact current scoped-CSS debt is eligible`,
      );
    }
    if (typeof entry.fingerprint !== "string" || !/^[0-9a-f]{64}$/.test(entry.fingerprint)) {
      throw new Error(`${entry.rule} debt needs one exact SHA-256 fingerprint`);
    }
    if (
      !Array.isArray(entry.locations) ||
      entry.locations.length === 0 ||
      entry.locations.some(
        (location) =>
          typeof location !== "string" ||
          !/^logos\/[a-z][a-z0-9-]*\/src\/(?:[a-z0-9_-]+\/)*[a-z0-9_-]+\.lg:[1-9][0-9]*$/.test(
            location,
          ),
      ) ||
      JSON.stringify([...entry.locations].sort(compareLocations)) !== JSON.stringify(entry.locations) ||
      new Set(entry.locations).size !== entry.locations.length
    ) {
      throw new Error(`${entry.rule} debt locations must be unique, sorted, exact LOGOS source lines`);
    }
    if (typeof entry.reason !== "string" || entry.reason.trim().length < 40) {
      throw new Error(`${entry.rule} debt needs a specific reason of at least 40 characters`);
    }
    if (typeof entry.removalCondition !== "string" || entry.removalCondition.trim().length < 40) {
      throw new Error(`${entry.rule} debt needs a concrete removal condition of at least 40 characters`);
    }
    const identity = `${entry.rule}:${entry.fingerprint}`;
    if (debtIdentities.has(identity)) throw new Error(`duplicate debt identity: ${identity}`);
    debtIdentities.add(identity);
  }
  return policy;
}

function sourceFiles(root, issues) {
  const logosRoot = join(root, "logos");
  if (!existsSync(logosRoot)) {
    issues.push({
      rule: "source-tree",
      locations: ["logos:1"],
      fingerprint: digest("missing-logos-source-root"),
      message: "logos/ is missing; restore the registered LOGOS project roots.",
    });
    return [];
  }
  const result = [];
  function visit(directory) {
    for (const entry of readdirSync(directory).sort()) {
      const path = join(directory, entry);
      const stats = lstatSync(path);
      if (stats.isSymbolicLink()) {
        issues.push({
          rule: "source-tree",
          locations: [`${repositoryPath(root, path)}:1`],
          fingerprint: digest(`symlink:${repositoryPath(root, path)}`),
          message: "LOGOS source symlinks are forbidden; use a reviewed, local source file.",
        });
      } else if (stats.isDirectory()) {
        visit(path);
      } else if (stats.isFile() && extname(path) === ".lg") {
        result.push(path);
      }
    }
  }
  visit(logosRoot);
  return result.sort();
}

function physicalLines(source) {
  const lines = source.split(/\r?\n/);
  if (lines.at(-1) === "") lines.pop();
  return lines;
}

function collapseWhitespaceOutsideStrings(text, quoteCharacters) {
  let result = "";
  let quote = null;
  let escaped = false;
  let pendingSpace = false;
  for (const character of text.trim()) {
    if (quote !== null) {
      result += character;
      if (escaped) {
        escaped = false;
      } else if (character === "\\") {
        escaped = true;
      } else if (character === quote) {
        quote = null;
      }
      continue;
    }
    if (quoteCharacters.has(character)) {
      if (pendingSpace && result.length > 0) result += " ";
      pendingSpace = false;
      quote = character;
      result += character;
    } else if (/\s/.test(character)) {
      pendingSpace = true;
    } else {
      if (pendingSpace && result.length > 0) result += " ";
      pendingSpace = false;
      result += character;
    }
  }
  return result;
}

function normalizedStatement(line) {
  return collapseWhitespaceOutsideStrings(line, new Set(['"', "'", "`"]));
}

function isRawStringPrefix(line, quoteIndex) {
  if (quoteIndex === 0 || line[quoteIndex - 1] !== "r") return false;
  return quoteIndex === 1 || !/[\p{L}\p{N}_]/u.test(line[quoteIndex - 2]);
}

function scanLogosLine(line) {
  let literal = null;
  let escaped = false;
  for (let index = 0; index < line.length; index += 1) {
    const character = line[index];
    if (literal === "escaped-string" || literal === "char") {
      if (escaped) {
        escaped = false;
      } else if (character === "\\") {
        escaped = true;
      } else if (
        (literal === "escaped-string" && character === '"') ||
        (literal === "char" && character === "`")
      ) {
        literal = null;
      }
      continue;
    }
    if (literal === "raw-string") {
      if (character === '"') literal = null;
      continue;
    }
    if (character === "#" && line[index + 1] === "#") {
      index += 1;
    } else if (character === "#") {
      return { commentIndex: index, tripleIndex: -1 };
    } else if (character === "`") {
      literal = "char";
    } else if (character === '"') {
      if (line.slice(index, index + 3) === '\"\"\"') {
        return { commentIndex: -1, tripleIndex: index };
      }
      literal = isRawStringPrefix(line, index) ? "raw-string" : "escaped-string";
    }
  }
  return { commentIndex: -1, tripleIndex: -1 };
}

function stripLogosInlineComment(line) {
  const { commentIndex } = scanLogosLine(line);
  return commentIndex < 0 ? line : line.slice(0, commentIndex);
}

function isDefinitionHeader(line) {
  return /^##\s+\S/.test(line);
}

function isBehaviorStatement(statement) {
  if (statement.endsWith(".")) return true;
  return /^(?:if|else|otherwise|when|on|for|while|repeat|match|case|try|catch|finally|let)\b.*(?::|->:)$/i.test(
    statement,
  );
}

function cssLiteral(line) {
  const raw = line.match(/^\s*css\s+r"([^"]*)"\s*$/);
  if (raw) return raw[1];
  const escaped = line.match(/^\s*css\s+"((?:[^"\\]|\\.)*)"\s*$/);
  return escaped ? escaped[1] : null;
}

function stripCssBlockComments(css) {
  const escapedDoubleQuote = "\u{e000}";
  const protectedCss = css.replaceAll('\\"', escapedDoubleQuote);
  const quoteCharacters = new Set(["'", '"', escapedDoubleQuote]);
  let result = "";
  let quote = null;
  let escaped = false;
  let inComment = false;

  for (let index = 0; index < protectedCss.length; index += 1) {
    const character = protectedCss[index];
    if (inComment) {
      if (character === "*" && protectedCss[index + 1] === "/") {
        inComment = false;
        index += 1;
        if (result.length > 0 && !/\s$/.test(result)) result += " ";
      }
      continue;
    }
    if (quote !== null) {
      result += character;
      if (escaped) {
        escaped = false;
      } else if (character === "\\") {
        escaped = true;
      } else if (character === quote) {
        quote = null;
      }
      continue;
    }
    if (quoteCharacters.has(character)) {
      quote = character;
      result += character;
    } else if (character === "\\" && index + 1 < protectedCss.length) {
      result += character + protectedCss[index + 1];
      index += 1;
    } else if (character === "/" && protectedCss[index + 1] === "*") {
      inComment = true;
      index += 1;
      if (result.length > 0 && !/\s$/.test(result)) result += " ";
    } else {
      result += character;
    }
  }

  return {
    css: result.replaceAll(escapedDoubleQuote, '\\"'),
    unterminatedComment: inComment,
  };
}

function normalizedCss(css) {
  const withoutComments = stripCssBlockComments(css);
  const escapedDoubleQuote = "\u{e000}";
  const protectedCss = withoutComments.css.replaceAll('\\"', escapedDoubleQuote);
  return {
    normalized: collapseWhitespaceOutsideStrings(
      protectedCss,
      new Set(["'", '"', escapedDoubleQuote]),
    ).replaceAll(escapedDoubleQuote, '\\"'),
    unterminatedComment: withoutComments.unterminatedComment,
  };
}

function declarationCount(css) {
  const escapedDoubleQuote = "\u{e000}";
  const protectedCss = css.replaceAll('\\"', escapedDoubleQuote);
  const quoteCharacters = new Set(["'", '"', escapedDoubleQuote]);
  let quote = null;
  let escaped = false;
  let declarations = 0;
  for (let index = 0; index < protectedCss.length; index += 1) {
    const character = protectedCss[index];
    if (quote !== null) {
      if (escaped) {
        escaped = false;
      } else if (character === "\\") {
        escaped = true;
      } else if (character === quote) {
        quote = null;
      }
    } else if (quoteCharacters.has(character)) {
      quote = character;
    } else if (character === "\\" && index + 1 < protectedCss.length) {
      index += 1;
    } else if (character === ";") {
      declarations += 1;
    }
  }
  return declarations;
}

function sourceLocation(path, line) {
  return `${path}:${line}`;
}

function tripleStringOpeningIndex(line) {
  return scanLogosLine(line).tripleIndex;
}

function scanTripleQuotedStrings(lines, portablePath, issues) {
  const ranges = [];
  let active = null;

  function finish(range, endIndex, suffix) {
    range.endIndex = endIndex;
    range.suffix = stripLogosInlineComment(suffix);
    range.body = range.bodyParts.join("\n");
    range.isCss = /^\s*css[ \t]+(?:r)?$/.test(range.prefix);
    if (range.isCss && range.suffix.trim().length > 0) {
      issues.push({
        rule: "malformed-triple-css",
        locations: [sourceLocation(portablePath, range.startIndex + 1)],
        fingerprint: digest(`${range.prefix}\n${range.body}\n${range.suffix}`),
        message:
          "triple-quoted css has tokens after its closing delimiter; keep the closing \"\"\" " +
          "on its own or at the end of the CSS literal.",
      });
    }
    ranges.push(range);
  }

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    if (active) {
      const closing = line.indexOf('"""');
      if (closing < 0) {
        active.bodyParts.push(line);
        continue;
      }
      active.bodyParts.push(line.slice(0, closing));
      finish(active, index, line.slice(closing + 3));
      active = null;
      continue;
    }

    const opening = tripleStringOpeningIndex(line);
    if (opening < 0) continue;
    const afterOpening = line.slice(opening + 3);
    const closing = afterOpening.indexOf('"""');
    const range = {
      startIndex: index,
      prefix: line.slice(0, opening),
      bodyParts: [],
    };
    if (closing >= 0) {
      range.bodyParts.push(afterOpening.slice(0, closing));
      finish(range, index, afterOpening.slice(closing + 3));
    } else {
      if (afterOpening.length > 0) range.bodyParts.push(afterOpening);
      active = range;
    }
  }

  if (active) {
    active.endIndex = Math.max(active.startIndex, lines.length - 1);
    active.suffix = "";
    active.body = active.bodyParts.join("\n");
    active.isCss = /^\s*css[ \t]+(?:r)?$/.test(active.prefix);
    ranges.push(active);
    issues.push({
      rule: "unterminated-triple-string",
      locations: [sourceLocation(portablePath, active.startIndex + 1)],
      fingerprint: digest(`${active.prefix}\n${active.body}`),
      message:
        "triple-quoted string reaches end of file; add the closing \"\"\" before any following LOGOS statement.",
    });
  }

  const byLine = new Map();
  for (const range of ranges) {
    range.statementToken = normalizedStatement(
      `${range.prefix}<triple-string:${digest(range.body)}>${range.suffix}`,
    );
    for (let index = range.startIndex; index <= range.endIndex; index += 1) {
      byLine.set(index, {
        range,
        isStart: index === range.startIndex,
        isEnd: index === range.endIndex,
      });
    }
  }
  return byLine;
}

function analyzeFile(root, path, policy, issues, cssByFingerprint, segments) {
  const portablePath = repositoryPath(root, path);
  const source = readFileSync(path, "utf8");
  const lines = physicalLines(source);
  if (lines.length > policy.files.maxPhysicalLines) {
    issues.push({
      rule: "max-physical-lines",
      locations: [sourceLocation(portablePath, 1)],
      fingerprint: digest(source),
      message:
        `${lines.length} physical lines exceeds ${policy.files.maxPhysicalLines}; ` +
        "split the module at a responsibility boundary and import the new .lg file.",
    });
  }

  const tripleByLine = scanTripleQuotedStrings(lines, portablePath, issues);
  const definitions = [];
  let currentDefinition = null;
  for (let index = 0; index < lines.length; index += 1) {
    const lineNumber = index + 1;
    const line = lines[index];
    const tripleLine = tripleByLine.get(index) ?? null;
    const codeLine = tripleLine === null ? stripLogosInlineComment(line) : line;
    const structuralLine = tripleLine
      ? tripleLine.isStart
        ? stripLogosInlineComment(tripleLine.range.prefix)
        : ""
      : codeLine;
    const trimmed = structuralLine.trim();
    if (isDefinitionHeader(trimmed)) {
      if (currentDefinition) definitions.push(currentDefinition);
      currentDefinition = {
        name: trimmed,
        line: lineNumber,
        logicalLines: 1,
        statements: [],
      };
    } else if (currentDefinition && trimmed.length > 0 && !/^#(?!#)/.test(trimmed)) {
      currentDefinition.logicalLines += 1;
    }

    const singleLineCss = tripleLine === null ? cssLiteral(codeLine) : null;
    const css = tripleLine?.isStart && tripleLine.range.isCss
      ? tripleLine.range.body
      : singleLineCss;
    const isTripleLine = tripleLine !== null;
    const isTripleCssLine = tripleLine?.range.isCss === true;
    if (css !== null) {
      const { normalized, unterminatedComment } = normalizedCss(css);
      const fingerprint = digest(normalized);
      if (unterminatedComment) {
        issues.push({
          rule: "unterminated-css-comment",
          locations: [sourceLocation(portablePath, lineNumber)],
          fingerprint: digest(css),
          message:
            "scoped CSS contains an unterminated /* comment; close it before CSS is " +
            "normalized or compared.",
        });
      }
      if (!isTripleLine && line.length > policy.scopedCss.hardMaxLineLength) {
        issues.push({
          rule: "scoped-css-hard-length",
          locations: [sourceLocation(portablePath, lineNumber)],
          fingerprint,
          message:
            `${line.length} characters exceeds the scoped-CSS hard limit ` +
            `${policy.scopedCss.hardMaxLineLength}; split this View into smaller child Components.`,
        });
      } else if (!isTripleLine && line.length > policy.scopedCss.preferredMaxLineLength) {
        issues.push({
          rule: "scoped-css-preferred-length",
          locations: [sourceLocation(portablePath, lineNumber)],
          fingerprint,
          debtEligible: true,
          message:
            `${line.length} characters exceeds the scoped-CSS design limit ` +
            `${policy.scopedCss.preferredMaxLineLength}; split the View into a cohesive child Component ` +
            "before changing this style string.",
        });
      }
      if (
        !unterminatedComment &&
        declarationCount(normalized) >= policy.scopedCss.duplicateMinimumDeclarations
      ) {
        const occurrence = {
          location: sourceLocation(portablePath, lineNumber),
          normalized,
        };
        const group = cssByFingerprint.get(fingerprint) ?? [];
        group.push(occurrence);
        cssByFingerprint.set(fingerprint, group);
      }
    }
    if (
      (isTripleLine || (!isTripleCssLine && css === null)) &&
      line.length > policy.files.maxLineLength
    ) {
      issues.push({
        rule: "max-line-length",
        locations: [sourceLocation(portablePath, lineNumber)],
        fingerprint: digest(normalizedStatement(codeLine)),
        message:
          `${line.length} characters exceeds ${policy.files.maxLineLength}; ` +
          (isTripleLine
            ? "wrap this triple-quoted literal onto shorter physical lines."
            : "extract prose, a helper definition, or a child Component instead of extending the line."),
      });
    }

    for (const marker of policy.markers) {
      if (new RegExp(marker.pattern, marker.flags).test(line)) {
        issues.push({
          rule: `forbidden-marker-${marker.id}`,
          locations: [sourceLocation(portablePath, lineNumber)],
          fingerprint: digest(normalizedStatement(line)),
          message:
            `unfinished marker ${marker.id} is forbidden in product LOGOS; ` +
            "implement the behavior or record bounded work in the issue/intake system.",
        });
      }
    }

    if (currentDefinition && css !== null) {
      currentDefinition.statements.push({
        token: `<scoped-css-boundary:${portablePath}:${lineNumber}>`,
        behavior: false,
        path: portablePath,
        line: lineNumber,
      });
    } else if (
      currentDefinition &&
      tripleLine?.isStart &&
      !tripleLine.range.isCss &&
      trimmed.length > 0 &&
      !isDefinitionHeader(trimmed) &&
      !/^#/.test(trimmed) &&
      !/^(?:View|Render):$/.test(trimmed)
    ) {
      currentDefinition.statements.push({
        token: tripleLine.range.statementToken,
        behavior: isBehaviorStatement(tripleLine.range.statementToken),
        path: portablePath,
        line: lineNumber,
      });
    } else if (
      currentDefinition &&
      tripleLine === null &&
      trimmed.length > 0 &&
      !isDefinitionHeader(trimmed) &&
      !/^#/.test(trimmed) &&
      !/^(?:View|Render):$/.test(trimmed) &&
      css === null
    ) {
      currentDefinition.statements.push({
        token: normalizedStatement(codeLine),
        behavior: isBehaviorStatement(trimmed),
        path: portablePath,
        line: lineNumber,
      });
    }
  }
  if (currentDefinition) definitions.push(currentDefinition);

  for (const definition of definitions) {
    if (definition.logicalLines > policy.files.maxLogicalLinesPerDefinition) {
      issues.push({
        rule: "max-logical-lines-per-definition",
        locations: [sourceLocation(portablePath, definition.line)],
        fingerprint: digest(`${definition.name}\n${definition.logicalLines}`),
        message:
          `${definition.name} has ${definition.logicalLines} logical lines, over ` +
          `${policy.files.maxLogicalLinesPerDefinition}; extract policy into a ## To helper ` +
          "or UI into an imported child ## Component.",
      });
    }
    if (definition.statements.length > 0) {
      segments.push({
        definition: definition.name,
        path: portablePath,
        statements: definition.statements,
      });
    }
  }
}

function findDuplicateBlocks(segments, policy) {
  const minimum = policy.duplicateBlocks.minimumStatements;
  const minimumBehavior = policy.duplicateBlocks.minimumBehaviorStatements;
  const matches = new Map();

  for (let leftSegment = 0; leftSegment < segments.length; leftSegment += 1) {
    const left = segments[leftSegment];
    for (let rightSegment = leftSegment; rightSegment < segments.length; rightSegment += 1) {
      const right = segments[rightSegment];
      for (let leftStart = 0; leftStart <= left.statements.length - minimum; leftStart += 1) {
        const firstRightStart = leftSegment === rightSegment ? leftStart + 1 : 0;
        for (
          let rightStart = firstRightStart;
          rightStart <= right.statements.length - minimum;
          rightStart += 1
        ) {
          if (left.statements[leftStart].token !== right.statements[rightStart].token) continue;
          if (
            leftStart > 0 &&
            rightStart > 0 &&
            left.statements[leftStart - 1].token === right.statements[rightStart - 1].token
          ) {
            continue;
          }
          let length = 0;
          while (
            leftStart + length < left.statements.length &&
            rightStart + length < right.statements.length &&
            left.statements[leftStart + length].token === right.statements[rightStart + length].token
          ) {
            length += 1;
          }
          if (length < minimum) continue;
          const tokens = left.statements
            .slice(leftStart, leftStart + length)
            .map((statement) => statement.token);
          const behaviorCount = left.statements
            .slice(leftStart, leftStart + length)
            .filter((statement) => statement.behavior).length;
          if (behaviorCount < minimumBehavior) continue;
          const fingerprint = digest(tokens.join("\n"));
          const group = matches.get(fingerprint) ?? {
            fingerprint,
            statementCount: length,
            occurrences: new Map(),
          };
          for (const [segment, start] of [
            [left, leftStart],
            [right, rightStart],
          ]) {
            const first = segment.statements[start];
            const last = segment.statements[start + length - 1];
            const key = `${first.path}:${first.line}-${last.line}`;
            group.occurrences.set(key, key);
          }
          matches.set(fingerprint, group);
        }
      }
    }
  }
  return [...matches.values()]
    .filter((group) => group.occurrences.size > policy.duplicateBlocks.maximumOccurrences)
    .map((group) => ({
      rule: "duplicate-statement-block",
      locations: [...group.occurrences.values()].sort(compareLocations),
      fingerprint: group.fingerprint,
      message:
        `${group.statementCount} normalized statements are copied across ` +
        `${group.occurrences.size} locations; extract one LOGOS ## To policy helper or child ` +
        "## Component and call it from each site.",
    }));
}

function reconcileDebt(policy, issues) {
  const active = [];
  const failures = [];
  const debtByIdentity = new Map(
    policy.debt.map((entry) => [`${entry.rule}:${entry.fingerprint}`, entry]),
  );
  const usedDebt = new Set();
  for (const issue of issues) {
    const identity = `${issue.rule}:${issue.fingerprint}`;
    const debt = debtByIdentity.get(identity);
    if (
      issue.debtEligible === true &&
      debt &&
      JSON.stringify(issue.locations) === JSON.stringify(debt.locations)
    ) {
      usedDebt.add(identity);
      active.push({ ...issue, debt });
    } else {
      failures.push(issue);
    }
  }
  for (const entry of policy.debt) {
    const identity = `${entry.rule}:${entry.fingerprint}`;
    if (!usedDebt.has(identity)) {
      failures.push({
        rule: "stale-source-debt",
        locations: entry.locations,
        fingerprint: entry.fingerprint,
        message:
          `${entry.rule} debt no longer matches the exact content and locations; ` +
          "remove the debt entry or review the changed source instead of broadening the exception.",
      });
    }
  }
  return { activeDebt: active, failures };
}

export function lintLogosSources({
  root = defaultRepositoryRoot,
  policyPath = defaultPolicyPath,
  moduleManifestPath = defaultModuleManifestPath,
  checkModuleGraph = true,
} = {}) {
  const canonicalRoot = realpathSync(root);
  const policy = loadSourcePolicy(policyPath);
  const issues = [];
  const cssByFingerprint = new Map();
  const segments = [];

  if (checkModuleGraph) {
    try {
      const manifest = loadModuleManifest(moduleManifestPath);
      inspectRegisteredProjects(manifest, canonicalRoot);
    } catch (error) {
      issues.push({
        rule: "module-closure",
        locations: [`${repositoryPath(canonicalRoot, moduleManifestPath)}:1`],
        fingerprint: digest(error.message),
        message: `LOGOS module/orphan audit failed: ${error.message}`,
      });
    }
  }

  const files = sourceFiles(canonicalRoot, issues);
  for (const path of files) {
    analyzeFile(canonicalRoot, path, policy, issues, cssByFingerprint, segments);
  }
  for (const [fingerprint, occurrences] of cssByFingerprint) {
    if (occurrences.length > policy.scopedCss.maximumIdenticalOccurrences) {
      issues.push({
        rule: "duplicate-scoped-css",
        locations: occurrences.map(({ location }) => location).sort(compareLocations),
        fingerprint,
        debtEligible: true,
        message:
          `the same scoped-CSS block appears ${occurrences.length} times; ` +
          "extract a shared style-capable Component when LOGOS can preserve its scoping semantics.",
      });
    }
  }
  issues.push(...findDuplicateBlocks(segments, policy));
  const reconciled = reconcileDebt(policy, issues);
  return {
    policy,
    filesChecked: files.length,
    failures: reconciled.failures.sort((left, right) =>
      `${left.locations[0]}:${left.rule}`.localeCompare(`${right.locations[0]}:${right.rule}`),
    ),
    activeDebt: reconciled.activeDebt.sort((left, right) =>
      `${left.locations[0]}:${left.rule}`.localeCompare(`${right.locations[0]}:${right.rule}`),
    ),
  };
}

function printIssue(prefix, issue) {
  process.stderr.write(
    `${prefix}: [${issue.rule}] ${issue.locations.join(", ")}: ${issue.message} ` +
      `(fingerprint ${issue.fingerprint})\n`,
  );
}

function main() {
  if (process.argv.length !== 2) {
    process.stderr.write("usage: node scripts/logos-source-lint.mjs\n");
    process.exit(2);
  }
  let result;
  try {
    result = lintLogosSources();
  } catch (error) {
    process.stderr.write(`error: LOGOS source linter could not start: ${error.message}\n`);
    process.exit(1);
  }
  for (const issue of result.activeDebt) printIssue("debt", issue);
  for (const issue of result.failures) printIssue("error", issue);
  if (result.failures.length > 0) {
    process.stderr.write(`LOGOS source lint failed with ${result.failures.length} violation(s)\n`);
    process.exit(1);
  }
  process.stdout.write(
    `LOGOS source lint passed: ${result.filesChecked} files, ` +
      `${result.activeDebt.length} exact baseline debt item(s)\n`,
  );
}

const invokedPath = process.argv[1] ? resolve(process.argv[1]) : "";
if (invokedPath === fileURLToPath(import.meta.url)) main();
