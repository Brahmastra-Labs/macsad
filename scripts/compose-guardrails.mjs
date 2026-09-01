#!/usr/bin/env node

import {
  existsSync,
  lstatSync,
  readFileSync,
  readdirSync,
} from "node:fs";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
export const defaultRepositoryRoot = resolve(scriptDirectory, "..");
export const defaultComposePath = join(
  defaultRepositoryRoot,
  "ops",
  "compose",
  "compose.yaml",
);

export const requiredServices = Object.freeze([
  "postgres",
  "migrate",
  "logos-gateway",
  "logos-sites",
  "pgadmin",
]);

const pinnedImagePattern =
  /^[a-z0-9][a-z0-9._:/-]*:[A-Za-z0-9][A-Za-z0-9._-]*@sha256:[0-9a-f]{64}$/;
const bindAddressPattern =
  /^\$\{MACSAD_BIND_IP(?:(?::?\?)[^}]*)?\}:(?:[0-9]+|\$\{MACSAD_[A-Z0-9_]+(?::-[0-9]+)?\}):[0-9]+(?:-[0-9]+)?(?:\/(?:tcp|udp))?$/;
const sensitiveEnvironmentName =
  /(?:^|_)(?:PASSWORD|PASSWD|PGPASSWORD|PGPASS|SECRET|TOKEN|API_KEY|PRIVATE_KEY|DATABASE_URL)(?:_|$)/;
const mutationWord =
  "(?:create|update|delete|remove|publish|approve|reject|transition|advance|assign|retry|cancel|start|stop|run|execute|archive|restore|import|mutat|command)";
const runtimeEnvironmentKeys = Object.freeze([
  "MACSAD_BIND_IP",
  "MACSAD_REPOSITORY_ROOT",
  "MACSAD_RUNTIME_DIR",
  "MACSAD_BUILD_DIR",
  "MACSAD_SECRETS_DIR",
  "MACSAD_SOURCE_REVISION",
  "LOGOS_WORKSPACE",
  "PGADMIN_DEFAULT_EMAIL",
]);

export class ComposeGuardrailError extends Error {
  constructor(violations) {
    const sorted = [...new Set(violations)].sort();
    super(
      `Compose guardrails failed with ${sorted.length} violation(s):\n${sorted
        .map((violation) => `- ${violation}`)
        .join("\n")}`,
    );
    this.name = "ComposeGuardrailError";
    this.violations = sorted;
  }
}

function stripYamlComment(rawLine) {
  let singleQuoted = false;
  let doubleQuoted = false;
  for (let index = 0; index < rawLine.length; index += 1) {
    const character = rawLine[index];
    if (character === "'" && !doubleQuoted) {
      if (singleQuoted && rawLine[index + 1] === "'") {
        index += 1;
      } else {
        singleQuoted = !singleQuoted;
      }
    } else if (character === '"' && !singleQuoted && rawLine[index - 1] !== "\\") {
      doubleQuoted = !doubleQuoted;
    } else if (character === "#" && !singleQuoted && !doubleQuoted) {
      return rawLine.slice(0, index).trimEnd();
    }
  }
  return rawLine.trimEnd();
}

function scalar(value) {
  const trimmed = value.trim();
  if (
    trimmed.length >= 2 &&
    ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
      (trimmed.startsWith("'") && trimmed.endsWith("'")))
  ) {
    return trimmed.slice(1, -1);
  }
  return trimmed;
}

function sameMembers(actual, expected) {
  return (
    actual.length === expected.length &&
    JSON.stringify([...actual].sort()) === JSON.stringify([...expected].sort())
  );
}

function repositoryLabel(path, repositoryRoot) {
  const label = relative(repositoryRoot, path).split(sep).join("/");
  return label === "" ? "." : label;
}

function sourceLines(source, sourcePath, violations) {
  const lines = [];
  for (const [zeroBasedLine, rawLine] of source.replace(/^\uFEFF/, "").split(/\r?\n/).entries()) {
    const lineNumber = zeroBasedLine + 1;
    if (rawLine.includes("\t")) {
      violations.push(`${sourcePath}:${lineNumber}: tabs make YAML structure ambiguous`);
    }
    const text = stripYamlComment(rawLine);
    if (text.trim() === "") continue;
    const indent = text.length - text.trimStart().length;
    if (indent % 2 !== 0) {
      violations.push(`${sourcePath}:${lineNumber}: indentation must use two-space levels`);
    }
    const trimmed = text.trim();
    if (/^(?:---|\.\.\.|%YAML\b)/.test(trimmed)) {
      violations.push(`${sourcePath}:${lineNumber}: YAML directives/documents are forbidden`);
    }
    if (/(?:^|\s)<<\s*:|:\s*&[A-Za-z0-9_-]+\b|(?:^|\s)-?\s*\*[A-Za-z0-9_-]+\b/.test(trimmed)) {
      violations.push(`${sourcePath}:${lineNumber}: YAML anchors, aliases, and merge keys are forbidden`);
    }
    if (/^[A-Za-z0-9_.-]+:\s*[>|][+-]?\s*$/.test(trimmed)) {
      violations.push(`${sourcePath}:${lineNumber}: multiline scalars are forbidden`);
    }
    lines.push({ indent, lineNumber, text, trimmed });
  }
  return lines;
}

function topLevelSections(lines, sourcePath, violations) {
  const sections = new Map();
  const topLevel = lines.filter((line) => line.indent === 0);
  for (let index = 0; index < topLevel.length; index += 1) {
    const line = topLevel[index];
    const match = /^([A-Za-z][A-Za-z0-9_-]*):(?:\s*(.*))?$/.exec(line.trimmed);
    if (!match) {
      violations.push(`${sourcePath}:${line.lineNumber}: unsupported top-level YAML structure`);
      continue;
    }
    const [, name, value = ""] = match;
    if (sections.has(name)) {
      violations.push(`${sourcePath}:${line.lineNumber}: duplicate top-level key ${name}`);
      continue;
    }
    const start = lines.indexOf(line);
    let end = lines.length;
    for (let cursor = start + 1; cursor < lines.length; cursor += 1) {
      if (lines[cursor].indent === 0) {
        end = cursor;
        break;
      }
    }
    sections.set(name, { line, lines: lines.slice(start + 1, end), value });
    if (name.startsWith("x-")) {
      violations.push(`${sourcePath}:${line.lineNumber}: Compose extension keys are forbidden`);
    }
  }
  return sections;
}

function namedBlocks(section, indent, label, sourcePath, violations) {
  const blocks = new Map();
  if (!section) return blocks;
  if (section.value !== "") {
    violations.push(`${sourcePath}:${section.line.lineNumber}: ${label} must be a block mapping`);
    return blocks;
  }
  let current;
  for (const line of section.lines) {
    if (line.indent < indent) {
      violations.push(`${sourcePath}:${line.lineNumber}: malformed ${label} indentation`);
      continue;
    }
    if (line.indent === indent) {
      const match = new RegExp(`^ {${indent}}([a-zA-Z0-9][a-zA-Z0-9_.-]*):\\s*$`).exec(line.text);
      if (!match) {
        violations.push(`${sourcePath}:${line.lineNumber}: ${label} entries must be block mappings`);
        current = undefined;
        continue;
      }
      const name = match[1];
      if (blocks.has(name)) {
        violations.push(`${sourcePath}:${line.lineNumber}: duplicate ${label} entry ${name}`);
        current = undefined;
        continue;
      }
      current = { line, lines: [] };
      blocks.set(name, current);
    } else if (current) {
      current.lines.push(line);
    } else {
      violations.push(`${sourcePath}:${line.lineNumber}: content appears before a ${label} entry`);
    }
  }
  return blocks;
}

function directProperties(block, indent, label, sourcePath, violations) {
  const properties = new Map();
  if (!block) return properties;
  let current;
  for (const line of block.lines) {
    if (line.indent === indent) {
      const match = new RegExp(`^ {${indent}}([a-zA-Z_][a-zA-Z0-9_-]*):(?:\\s*(.*))?$`).exec(
        line.text,
      );
      if (!match) {
        violations.push(`${sourcePath}:${line.lineNumber}: unsupported ${label} structure`);
        current = undefined;
        continue;
      }
      const [, name, value = ""] = match;
      if (properties.has(name)) {
        violations.push(`${sourcePath}:${line.lineNumber}: duplicate ${label} key ${name}`);
        current = undefined;
        continue;
      }
      current = { line, lines: [], value };
      properties.set(name, current);
      if (name.startsWith("x-")) {
        violations.push(`${sourcePath}:${line.lineNumber}: Compose extension keys are forbidden`);
      }
    } else if (line.indent > indent && current) {
      current.lines.push(line);
    } else {
      violations.push(`${sourcePath}:${line.lineNumber}: malformed ${label} indentation`);
    }
  }
  return properties;
}

function simpleList(property, indent, label, sourcePath, violations) {
  if (!property) return [];
  if (property.value !== "") {
    violations.push(`${sourcePath}:${property.line.lineNumber}: ${label} must use block-list syntax`);
    return [];
  }
  const values = [];
  for (const line of property.lines) {
    const match = new RegExp(`^ {${indent}}-\\s+(.+?)\\s*$`).exec(line.text);
    if (line.indent !== indent || !match || /^[-{[]/.test(match?.[1] ?? "")) {
      violations.push(`${sourcePath}:${line.lineNumber}: ${label} must contain only scalar list entries`);
      continue;
    }
    values.push({ line, value: scalar(match[1]) });
  }
  return values;
}

function mappingEntries(
  property,
  indent,
  label,
  sourcePath,
  violations,
  { allowNested = false } = {},
) {
  if (!property) return new Map();
  if (property.value !== "") {
    violations.push(`${sourcePath}:${property.line.lineNumber}: ${label} must use block-mapping syntax`);
    return new Map();
  }
  const entries = new Map();
  for (const line of property.lines) {
    if (allowNested && line.indent > indent) continue;
    const match = new RegExp(`^ {${indent}}([A-Za-z_][A-Za-z0-9_.-]*):(?:\\s*(.*))?$`).exec(
      line.text,
    );
    if (line.indent !== indent || !match) {
      violations.push(`${sourcePath}:${line.lineNumber}: unsupported ${label} structure`);
      continue;
    }
    const [, name, value = ""] = match;
    if (entries.has(name)) {
      violations.push(`${sourcePath}:${line.lineNumber}: duplicate ${label} key ${name}`);
      continue;
    }
    entries.set(name, { line, value: scalar(value) });
  }
  return entries;
}

function inspectImage(serviceName, properties, sourcePath, violations) {
  const image = properties.get("image");
  const build = properties.get("build");
  if (!image && !build) {
    violations.push(`${sourcePath}: service ${serviceName} must declare an image or a staged build`);
    return;
  }
  if (!image) return;
  if (image.lines.length > 0 || image.value === "") {
    violations.push(`${sourcePath}:${image.line.lineNumber}: image must be one pinned scalar`);
    return;
  }
  const value = scalar(image.value);
  const localBuildImage = new RegExp(
    `^macsad/${serviceName}:\\$\\{MACSAD_SOURCE_REVISION:\\?[^}]+\\}$`,
  ).test(value);
  const migrationImage =
    serviceName === "migrate" &&
    /^macsad\/postgres:\$\{MACSAD_SOURCE_REVISION:\?[^}]+\}$/.test(value);
  if (!pinnedImagePattern.test(value) && !(build && localBuildImage) && !migrationImage) {
    violations.push(
      `${sourcePath}:${image.line.lineNumber}: pulled images require a tag and sha256 digest; local images require a matching build and required source-revision tag`,
    );
  }
  const tag = /:([^:@/]+)@sha256:/.exec(value)?.[1];
  if (
    pinnedImagePattern.test(value) &&
    (!tag || /^(?:latest|stable|edge|main|master|nightly)$/i.test(tag))
  ) {
    violations.push(`${sourcePath}:${image.line.lineNumber}: floating image tag ${tag ?? value} is forbidden`);
  }
}

function stagedContextPath(value) {
  const match = /^\$\{MACSAD_BUILD_DIR:\?[^}\r\n]+\}\/([a-z0-9][a-z0-9-]*)$/.exec(value);
  return match?.[1];
}

function inspectBuild(
  serviceName,
  property,
  composeAbsolutePath,
  repositoryRoot,
  sourcePath,
  violations,
) {
  if (!property) return new Map();
  const entries = mappingEntries(
    property,
    6,
    `${serviceName}.build`,
    sourcePath,
    violations,
    { allowNested: true },
  );
  const context = entries.get("context");
  if (!context || context.value === "") {
    violations.push(`${sourcePath}: service ${serviceName} build requires an explicit context`);
  } else if (
    context.value !== "." ||
    resolve(dirname(composeAbsolutePath)) !== resolve(repositoryRoot, "ops", "compose")
  ) {
    violations.push(
      `${sourcePath}:${context.line.lineNumber}: primary build context must be the committed ops/compose directory`,
    );
  }

  const additionalProperty = (() => {
    if (!property || property.value !== "") return undefined;
    const start = property.lines.findIndex(
      (line) => line.indent === 6 && /^ {6}additional_contexts:\s*$/.test(line.text),
    );
    if (start < 0) return undefined;
    const line = property.lines[start];
    const lines = [];
    for (let index = start + 1; index < property.lines.length; index += 1) {
      const candidate = property.lines[index];
      if (candidate.indent <= 6) break;
      lines.push(candidate);
    }
    return { line, lines, value: "" };
  })();

  const additionalContexts = mappingEntries(
    additionalProperty,
    8,
    `${serviceName}.build.additional_contexts`,
    sourcePath,
    violations,
  );
  for (const [name, entry] of additionalContexts) {
    const stagedName = stagedContextPath(entry.value);
    if (!stagedName || stagedName !== name) {
      violations.push(
        `${sourcePath}:${entry.line.lineNumber}: additional build context ${name} must use required \${MACSAD_BUILD_DIR:?…}/${name}`,
      );
    }
  }
  return additionalContexts;
}

function inspectPorts(serviceName, property, sourcePath, violations) {
  if (!property) return [];
  if (serviceName === "postgres") {
    violations.push(`${sourcePath}:${property.line.lineNumber}: PostgreSQL must not publish a host port`);
  }
  const ports = simpleList(property, 6, `${serviceName}.ports`, sourcePath, violations);
  for (const { line, value } of ports) {
    if (!bindAddressPattern.test(value)) {
      violations.push(
        `${sourcePath}:${line.lineNumber}: published port must bind through required \${MACSAD_BIND_IP:?…} without a fallback`,
      );
      continue;
    }
    const target = /:([0-9]+)(?:-[0-9]+)?(?:\/(?:tcp|udp))?$/.exec(value)?.[1];
    if (target === "5432") {
      violations.push(`${sourcePath}:${line.lineNumber}: direct PostgreSQL publication is forbidden`);
    }
  }
  return ports;
}

function inspectEnvironment(serviceName, property, secretNames, sourcePath, violations) {
  const environment = mappingEntries(
    property,
    6,
    `${serviceName}.environment`,
    sourcePath,
    violations,
  );
  for (const [name, entry] of environment) {
    if (name === "PGADMIN_CONFIG_ALLOW_SAVE_PASSWORD") {
      if (!/^(?:false|"False"|'False')$/i.test(entry.value)) {
        violations.push(`${sourcePath}:${entry.line.lineNumber}: pgAdmin password saving must remain disabled`);
      }
      continue;
    }
    if (!sensitiveEnvironmentName.test(name)) continue;
    if (!name.endsWith("_FILE")) {
      violations.push(
        `${sourcePath}:${entry.line.lineNumber}: sensitive environment value ${name} must be file-backed`,
      );
      continue;
    }
    const match = /^\/run\/secrets\/([a-zA-Z0-9_.-]+)$/.exec(entry.value);
    if (!match) {
      violations.push(
        `${sourcePath}:${entry.line.lineNumber}: ${name} must reference /run/secrets/<name>`,
      );
    } else if (!secretNames.has(match[1])) {
      violations.push(
        `${sourcePath}:${entry.line.lineNumber}: ${name} references an undeclared service secret ${match[1]}`,
      );
    }
  }
  return environment;
}

function inspectServiceSecrets(serviceName, property, declaredSecrets, sourcePath, violations) {
  const values = simpleList(property, 6, `${serviceName}.secrets`, sourcePath, violations);
  const names = new Set();
  for (const { line, value } of values) {
    if (!/^[a-zA-Z0-9][a-zA-Z0-9_.-]*$/.test(value)) {
      violations.push(`${sourcePath}:${line.lineNumber}: service secret references must use short names`);
      continue;
    }
    if (!declaredSecrets.has(value)) {
      violations.push(`${sourcePath}:${line.lineNumber}: service references undeclared secret ${value}`);
    }
    names.add(value);
  }
  return names;
}

function inspectTopLevelSecrets(blocks, sourcePath, violations) {
  const names = new Set(blocks.keys());
  for (const [name, block] of blocks) {
    const properties = directProperties(block, 4, `secret ${name}`, sourcePath, violations);
    const file = properties.get("file");
    if (!file || file.value === "" || file.lines.length > 0) {
      violations.push(`${sourcePath}: secret ${name} must have exactly one file source`);
      continue;
    }
    const value = scalar(file.value);
    const match = /^\$\{MACSAD_SECRETS_DIR:\?[^}\r\n]+\}\/([a-zA-Z0-9_.-]+)$/.exec(value);
    if (!match || match[1] !== name) {
      violations.push(
        `${sourcePath}:${file.line.lineNumber}: secret ${name} must use required \${MACSAD_SECRETS_DIR:?…}/${name}`,
      );
    }
    for (const key of properties.keys()) {
      if (key !== "file") {
        violations.push(`${sourcePath}: secret ${name} may only declare a file source`);
      }
    }
  }
  return names;
}

function inspectNetworks(blocks, sourcePath, violations) {
  if (!sameMembers([...blocks.keys()], ["data", "edge"])) {
    violations.push(`${sourcePath}: top-level networks must be exactly data and edge`);
  }
  for (const networkName of ["data", "edge"]) {
    const block = blocks.get(networkName);
    if (!block) continue;
    const properties = directProperties(
      block,
      4,
      `network ${networkName}`,
      sourcePath,
      violations,
    );
    const internal = properties.get("internal");
    if (
      properties.size !== 1 ||
      !internal ||
      scalar(internal.value).toLowerCase() !== "true" ||
      internal.lines.length > 0
    ) {
      violations.push(`${sourcePath}: ${networkName} network must declare only internal: true`);
    }
  }
}

function inspectVolumes(blocks, sourcePath, violations) {
  if (!sameMembers([...blocks.keys()], ["postgres_data", "pgadmin_data"])) {
    violations.push(`${sourcePath}: top-level volumes must be exactly postgres_data and pgadmin_data`);
  }
  for (const [name, block] of blocks) {
    if (block.lines.length > 0) {
      violations.push(
        `${sourcePath}:${block.line.lineNumber}: volume ${name} must be engine-managed with no driver, driver_opts, device, or external source`,
      );
    }
  }
}

function inspectHardening(serviceName, properties, sourcePath, violations) {
  const readOnlyServices = new Set(["migrate", "logos-gateway", "logos-sites"]);
  const isolatedServices = new Set(["migrate", "logos-gateway", "logos-sites", "pgadmin"]);
  const shouldBeReadOnly = readOnlyServices.has(serviceName);
  const shouldIsolate = isolatedServices.has(serviceName);
  const readOnly = properties.get("read_only");
  if (shouldBeReadOnly) {
    if (!readOnly || readOnly.lines.length > 0 || scalar(readOnly.value).toLowerCase() !== "true") {
      violations.push(`${sourcePath}: service ${serviceName} must declare read_only: true`);
    }
  } else if (readOnly) {
    violations.push(`${sourcePath}: service ${serviceName} must not override the read_only contract`);
  }

  const capDrop = simpleList(
    properties.get("cap_drop"),
    6,
    `${serviceName}.cap_drop`,
    sourcePath,
    violations,
  ).map((entry) => entry.value);
  const securityOptions = simpleList(
    properties.get("security_opt"),
    6,
    `${serviceName}.security_opt`,
    sourcePath,
    violations,
  ).map((entry) => entry.value);
  if (shouldIsolate) {
    if (!sameMembers(capDrop, ["ALL"])) {
      violations.push(`${sourcePath}: service ${serviceName} must drop exactly ALL capabilities`);
    }
    if (!sameMembers(securityOptions, ["no-new-privileges:true"])) {
      violations.push(
        `${sourcePath}: service ${serviceName} must set exactly no-new-privileges:true`,
      );
    }
  } else if (capDrop.length > 0 || securityOptions.length > 0) {
    violations.push(`${sourcePath}: service ${serviceName} diverges from its capability contract`);
  }
}

function inspectPgAdminConfigReference(configBlocks, pgadminProperties, sourcePath, violations) {
  const configs = pgadminProperties.get("configs");
  if (!configs || configs.value !== "") {
    violations.push(`${sourcePath}: pgadmin must mount a file-backed servers.json config`);
    return undefined;
  }
  let sourceName;
  let target;
  for (let index = 0; index < configs.lines.length; index += 1) {
    const line = configs.lines[index];
    const sourceMatch = /^ {6}-\s+source:\s*([a-zA-Z0-9_.-]+)\s*$/.exec(line.text);
    if (sourceMatch) {
      if (sourceName) {
        violations.push(`${sourcePath}:${line.lineNumber}: pgadmin must mount one servers config`);
      }
      sourceName = sourceMatch[1];
      continue;
    }
    const targetMatch = /^ {8}target:\s*(.+?)\s*$/.exec(line.text);
    if (targetMatch) {
      if (target !== undefined) {
        violations.push(`${sourcePath}:${line.lineNumber}: duplicate pgadmin config target`);
      }
      target = scalar(targetMatch[1]);
      continue;
    }
    if (!/^ {8}(?:uid|gid|mode):\s*.+$/.test(line.text)) {
      violations.push(`${sourcePath}:${line.lineNumber}: unsupported pgadmin config mount structure`);
    }
  }
  if (!sourceName || target !== "/pgadmin4/servers.json") {
    violations.push(`${sourcePath}: pgadmin servers config must target /pgadmin4/servers.json`);
    return undefined;
  }
  const block = configBlocks.get(sourceName);
  if (!block) {
    violations.push(`${sourcePath}: pgadmin references undeclared config ${sourceName}`);
    return undefined;
  }
  const properties = directProperties(block, 4, `config ${sourceName}`, sourcePath, violations);
  const file = properties.get("file");
  if (!file || file.value === "" || file.lines.length > 0) {
    violations.push(`${sourcePath}: pgadmin servers config must be backed by one JSON file`);
    return undefined;
  }
  if (properties.size !== 1) {
    violations.push(`${sourcePath}: pgadmin servers config may declare only its file source`);
  }
  return scalar(file.value);
}

function hasForbiddenGetMutation(text) {
  const flattened = text.replace(/\s+/g, " ");
  const forward = new RegExp(`\\bGET\\b[^\\n]{0,180}\\b${mutationWord}\\b`, "i");
  const reverse = new RegExp(`\\b${mutationWord}\\b[^\\n]{0,180}\\bGET\\b`, "i");
  return forward.test(flattened) || reverse.test(flattened);
}

function readDeployFiles(directory) {
  if (!existsSync(directory)) return [];
  const result = [];
  for (const entry of readdirSync(directory, { withFileTypes: true }).sort((left, right) =>
    left.name.localeCompare(right.name),
  )) {
    if (entry.name === ".runtime" || entry.name === "node_modules") continue;
    const path = join(directory, entry.name);
    if (entry.isDirectory()) {
      result.push(...readDeployFiles(path));
    } else if (
      entry.isFile() &&
      (/(?:^Dockerfile|\.dockerfile|\.conf|\.sh|\.ya?ml|\.json)$/i.test(entry.name))
    ) {
      result.push(path);
    }
  }
  return result;
}

export function inspectComposeSource(
  source,
  {
    sourcePath = "ops/compose/compose.yaml",
    repositoryRoot = defaultRepositoryRoot,
  } = {},
) {
  if (typeof source !== "string") throw new TypeError("Compose source must be a string");
  const violations = [];
  const composeAbsolutePath = isAbsolute(sourcePath)
    ? resolve(sourcePath)
    : resolve(repositoryRoot, sourcePath);
  const label = isAbsolute(sourcePath)
    ? repositoryLabel(composeAbsolutePath, repositoryRoot)
    : sourcePath.split("\\").join("/");
  const lines = sourceLines(source, label, violations);
  const sections = topLevelSections(lines, label, violations);

  for (const forbidden of ["include", "extends"]) {
    if (sections.has(forbidden)) violations.push(`${label}: top-level ${forbidden} is forbidden`);
  }
  const serviceBlocks = namedBlocks(sections.get("services"), 2, "services", label, violations);
  const actualServices = [...serviceBlocks.keys()].sort();
  const expectedServices = [...requiredServices].sort();
  if (JSON.stringify(actualServices) !== JSON.stringify(expectedServices)) {
    violations.push(
      `${label}: services must be exactly ${requiredServices.join(", ")}; found ${actualServices.join(", ") || "none"}`,
    );
  }

  const secretBlocks = namedBlocks(sections.get("secrets"), 2, "secrets", label, violations);
  const declaredSecrets = inspectTopLevelSecrets(secretBlocks, label, violations);
  const expectedSecrets = [
    "postgres_superuser_password",
    "macsad_deployer_password",
    "macsad_runtime_password",
    "macsad_viewer_password",
    "pgadmin_admin_password",
  ];
  if (!sameMembers([...declaredSecrets], expectedSecrets)) {
    violations.push(`${label}: top-level secrets must be exactly ${expectedSecrets.join(", ")}`);
  }
  const networkBlocks = namedBlocks(sections.get("networks"), 2, "networks", label, violations);
  inspectNetworks(networkBlocks, label, violations);
  const configBlocks = namedBlocks(sections.get("configs"), 2, "configs", label, violations);
  if (!sameMembers([...configBlocks.keys()], ["pgadmin_servers"])) {
    violations.push(`${label}: top-level configs must contain only pgadmin_servers`);
  }
  const volumeBlocks = namedBlocks(sections.get("volumes"), 2, "volumes", label, violations);
  inspectVolumes(volumeBlocks, label, violations);
  const serviceDetails = new Map();

  for (const [serviceName, block] of serviceBlocks) {
    const properties = directProperties(block, 4, `service ${serviceName}`, label, violations);
    inspectImage(serviceName, properties, label, violations);
    const additionalContexts = inspectBuild(
      serviceName,
      properties.get("build"),
      composeAbsolutePath,
      repositoryRoot,
      label,
      violations,
    );
    const ports = inspectPorts(serviceName, properties.get("ports"), label, violations);
    const serviceSecrets = inspectServiceSecrets(
      serviceName,
      properties.get("secrets"),
      declaredSecrets,
      label,
      violations,
    );
    const environment = inspectEnvironment(
      serviceName,
      properties.get("environment"),
      serviceSecrets,
      label,
      violations,
    );
    const networkList = simpleList(
      properties.get("networks"),
      6,
      `${serviceName}.networks`,
      label,
      violations,
    ).map((entry) => entry.value);
    const networks = new Set(networkList);
    const volumes = simpleList(
      properties.get("volumes"),
      6,
      `${serviceName}.volumes`,
      label,
      violations,
    );
    volumes.forEach(({ line, value }) => {
        const sourceName = value.split(":", 1)[0];
        if (!/^[a-zA-Z0-9][a-zA-Z0-9_.-]*$/.test(sourceName)) {
          violations.push(
            `${label}:${line.lineNumber}: runtime bind mounts are forbidden; bake verified staged artifacts into images`,
          );
        }
      });
    inspectHardening(serviceName, properties, label, violations);

    for (const forbiddenKey of [
      "privileged",
      "cap_add",
      "devices",
      "env_file",
      "extends",
      "ipc",
      "pid",
      "profiles",
    ]) {
      if (properties.has(forbiddenKey)) {
        violations.push(`${label}: service ${serviceName} may not declare ${forbiddenKey}`);
      }
    }
    const networkMode = properties.get("network_mode");
    if (networkMode) {
      const mode = scalar(networkMode.value);
      if (serviceName !== "logos-sites" || mode !== "service:logos-gateway") {
        violations.push(`${label}: service ${serviceName} has forbidden network_mode ${mode || "block"}`);
      }
    }
    if (serviceName !== "pgadmin" && properties.has("configs")) {
      violations.push(`${label}: service ${serviceName} may not mount Compose configs`);
    }
    serviceDetails.set(serviceName, {
      additionalContexts,
      block,
      environment,
      networkList,
      networks,
      ports,
      properties,
      serviceSecrets,
      volumes,
    });
  }

  const expectedServiceNetworks = new Map([
    ["postgres", ["data"]],
    ["migrate", ["data"]],
    ["logos-gateway", ["data", "edge"]],
    ["logos-sites", []],
    ["pgadmin", ["data"]],
  ]);
  for (const [serviceName, expected] of expectedServiceNetworks) {
    const actual = serviceDetails.get(serviceName)?.networkList ?? [];
    if (!sameMembers(actual, expected)) {
      violations.push(
        `${label}: service ${serviceName} networks must be exactly ${expected.join(", ") || "none"}`,
      );
    }
  }

  const bindTokenPattern = /^\$\{MACSAD_BIND_IP(?:(?::?\?)[^}]*)?\}/;
  const expectedPorts = new Map([
    ["postgres", []],
    ["migrate", []],
    ["logos-gateway", ["${MACSAD_BIND_IP}:18080:8080", "${MACSAD_BIND_IP}:18082:8082"]],
    ["logos-sites", []],
    ["pgadmin", ["${MACSAD_BIND_IP}:8978:8080"]],
  ]);
  for (const [serviceName, expected] of expectedPorts) {
    const actual = (serviceDetails.get(serviceName)?.ports ?? []).map(({ value }) =>
      value.replace(bindTokenPattern, "${MACSAD_BIND_IP}"),
    );
    if (!sameMembers(actual, expected)) {
      violations.push(
        `${label}: service ${serviceName} published ports must be exactly ${expected.join(", ") || "none"}`,
      );
    }
  }

  const expectedServiceVolumes = new Map([
    ["postgres", ["postgres_data:/var/lib/postgresql/data"]],
    ["migrate", []],
    ["logos-gateway", []],
    ["logos-sites", []],
    ["pgadmin", ["pgadmin_data:/var/lib/pgadmin"]],
  ]);
  for (const [serviceName, expected] of expectedServiceVolumes) {
    const actual = (serviceDetails.get(serviceName)?.volumes ?? []).map(({ value }) => value);
    if (!sameMembers(actual, expected)) {
      violations.push(
        `${label}: service ${serviceName} volumes must be exactly ${expected.join(", ") || "none"}`,
      );
    }
  }

  const expectedServiceSecrets = new Map([
    [
      "postgres",
      [
        "postgres_superuser_password",
        "macsad_deployer_password",
        "macsad_runtime_password",
        "macsad_viewer_password",
      ],
    ],
    ["migrate", ["macsad_deployer_password"]],
    ["logos-gateway", []],
    ["logos-sites", []],
    ["pgadmin", ["pgadmin_admin_password"]],
  ]);
  for (const [serviceName, expected] of expectedServiceSecrets) {
    const actual = [...(serviceDetails.get(serviceName)?.serviceSecrets ?? [])];
    if (!sameMembers(actual, expected)) {
      violations.push(
        `${label}: service ${serviceName} secrets must be exactly ${expected.join(", ") || "none"}`,
      );
    }
  }

  const migrationUser = serviceDetails.get("migrate")?.environment.get("PGUSER")?.value;
  if (migrationUser !== "macsad_deployer") {
    violations.push(`${label}: migrate PGUSER must be exactly macsad_deployer`);
  }
  const sites = serviceDetails.get("logos-sites");
  if (sites) {
    if (
      sites.properties.has("ports") ||
      sites.properties.has("networks") ||
      sites.properties.has("environment") ||
      sites.properties.has("secrets")
    ) {
      violations.push(`${label}: logos-sites must publish no ports or networks of its own`);
    }
    if (scalar(sites.properties.get("network_mode")?.value ?? "") !== "service:logos-gateway") {
      violations.push(`${label}: logos-sites must share only the logos-gateway network namespace`);
    }
    const siteText = sites.block.lines.map((line) => line.trimmed).join("\n");
    if (/\b(?:postgres|5432|DATABASE_URL|PGHOST|PGUSER|PGPASSWORD)\b/i.test(siteText)) {
      violations.push(`${label}: logos-sites may not receive a direct database connection`);
    }
  }

  for (const serviceName of ["postgres", "logos-gateway", "logos-sites"]) {
    if (!serviceDetails.get(serviceName)?.properties.has("build")) {
      violations.push(`${label}: service ${serviceName} must build only from verified staged artifacts`);
    }
  }
  const postgresImage = scalar(serviceDetails.get("postgres")?.properties.get("image")?.value ?? "");
  const migrationImage = scalar(serviceDetails.get("migrate")?.properties.get("image")?.value ?? "");
  if (postgresImage === "" || migrationImage !== postgresImage) {
    violations.push(`${label}: migrate must reuse the exact locally built postgres image`);
  }
  const expectedAdditionalContexts = new Map([
    ["postgres", ["database-source"]],
    ["logos-gateway", ["gateway-source", "logos-runtime"]],
    ["logos-sites", ["admin-bundle", "public-bundle"]],
  ]);
  for (const [serviceName, expected] of expectedAdditionalContexts) {
    const actual = [...(serviceDetails.get(serviceName)?.additionalContexts.keys() ?? [])].sort();
    if (JSON.stringify(actual) !== JSON.stringify([...expected].sort())) {
      violations.push(
        `${label}: service ${serviceName} additional contexts must be exactly ${expected.join(", ")}`,
      );
    }
  }
  const gatewayContexts = serviceDetails.get("logos-gateway")?.additionalContexts;
  const logosRuntime = gatewayContexts?.get("logos-runtime");
  if (!logosRuntime || !/(?:^|[\\/])logos-runtime(?:[\\/]|$)/.test(logosRuntime.value)) {
    violations.push(`${label}: logos-gateway must consume the staged logos-runtime context`);
  }

  const forbiddenSourceChecks = [
    [
      "Docker socket",
      /(?:\/var\/run\/(?:docker|podman)\.sock|docker_engine(?:\.sock)?|\bDOCKER_HOST\b)/i,
    ],
    ["private LOGOS checkout", /(?:LOGOS_WORKSPACE|logicaffeine-private)/i],
    ["private MaCSad checkout", /(?:MACSAD_REPO(?:SITORY)?|Brahmastra-Labs[\\/]macsad|\.git(?::|[\\/]))/i],
    ["registry LOGOS dependency", /(?:crates\.io|cargo\s+(?:add|install)\s+[^\n]*(?:logos|largo|logicaffeine))/i],
    ["password command argument", /--(?:password|passwd)(?:=|\s+)(?!file\b)/i],
  ];
  const uncommented = lines.map((line) => line.text).join("\n");
  for (const [description, pattern] of forbiddenSourceChecks) {
    if (pattern.test(uncommented)) violations.push(`${label}: forbidden ${description}`);
  }
  if (hasForbiddenGetMutation(uncommented)) {
    violations.push(`${label}: GET may not be used for a mutation or command route`);
  }
  if (/\bPOSTGRES_HOST_AUTH_METHOD\s*:\s*["']?trust\b/i.test(uncommented)) {
    violations.push(`${label}: PostgreSQL trust authentication is forbidden`);
  }

  const pgadminConfigFile = serviceDetails.has("pgadmin")
    ? inspectPgAdminConfigReference(
        configBlocks,
        serviceDetails.get("pgadmin").properties,
        label,
        violations,
      )
    : undefined;

  if (violations.length > 0) throw new ComposeGuardrailError(violations);
  return {
    pgadminConfigFile,
    services: requiredServices,
    stagedRuntimeRoot: relative(repositoryRoot, resolve(repositoryRoot, ".runtime", "compose", "build"))
      .split(sep)
      .join("/"),
  };
}

function walkJson(value, path, violations) {
  if (Array.isArray(value)) {
    value.forEach((entry, index) => walkJson(entry, `${path}[${index}]`, violations));
    return;
  }
  if (value === null || typeof value !== "object") {
    if (typeof value === "string" && /:\/\/[^/@\s]+:[^/@\s]+@/.test(value)) {
      violations.push(`${path}: URL contains embedded credentials`);
    }
    return;
  }
  for (const [key, entry] of Object.entries(value)) {
    const childPath = `${path}.${key}`;
    if (/(?:password|passwd|passfile|pgpass|secret|token|private.?key)/i.test(key)) {
      violations.push(`${childPath}: credential-bearing pgAdmin fields are forbidden`);
    }
    walkJson(entry, childPath, violations);
  }
}

export function inspectPgAdminServers(source, { sourcePath = "pgadmin/servers.json" } = {}) {
  const violations = [];
  let document;
  try {
    document = JSON.parse(source);
  } catch (error) {
    throw new ComposeGuardrailError([`${sourcePath}: invalid JSON: ${error.message}`]);
  }
  walkJson(document, sourcePath, violations);
  const servers = document?.Servers;
  if (!servers || typeof servers !== "object" || Array.isArray(servers) || Object.keys(servers).length === 0) {
    violations.push(`${sourcePath}: at least one pgAdmin server definition is required`);
  } else {
    for (const [serverId, server] of Object.entries(servers)) {
      if (!server || typeof server !== "object" || server.Host !== "postgres") {
        violations.push(`${sourcePath}.Servers.${serverId}: Host must be the internal postgres service`);
      }
      if (server?.Port !== 5432) {
        violations.push(`${sourcePath}.Servers.${serverId}: Port must be PostgreSQL's internal 5432`);
      }
      if (server?.Username !== "macsad_viewer" || server?.SharedUsername !== "macsad_viewer") {
        violations.push(
          `${sourcePath}.Servers.${serverId}: Username and SharedUsername must be macsad_viewer`,
        );
      }
    }
  }
  if (violations.length > 0) throw new ComposeGuardrailError(violations);
  return { serverCount: Object.keys(servers).length };
}

function inspectRuntimeEnvironmentParser(source, sourcePath, violations) {
  const executable = source
    .split(/\r?\n/)
    .filter((line) => !/^\s*#/.test(line))
    .join("\n");
  if (/^\s*(?:(?:builtin|command)\s+)?(?:source|\.)\s+/m.test(executable)) {
    violations.push(`${sourcePath}: runtime environment must never be sourced as shell code`);
  }
  if (/(?:^|[;&|]\s*)(?:(?:builtin|command)\s+)?eval(?:\s|$)/m.test(executable)) {
    violations.push(`${sourcePath}: eval is forbidden in the deployment harness`);
  }
  if (/(?:^|[;&|]\s*)set\s+-a(?:\s|$)/m.test(executable)) {
    violations.push(`${sourcePath}: automatic export is forbidden; assign allowlisted keys explicitly`);
  }

  for (const [description, pattern] of [
    [
      "runtime environment must be a regular non-symlink file",
      /\[\[ -f "\$\{(?:env_file|RUNTIME_ENV)\}" && ! -L "\$\{(?:env_file|RUNTIME_ENV)\}" \]\]/,
    ],
    [
      "runtime environment permissions must be exactly 0600",
      /stat -c '%a' -- "\$\{(?:env_file|RUNTIME_ENV)\}"\)" == '600'/,
    ],
    [
      "runtime environment must be read one complete line at a time",
      /while IFS= read -r line \|\| \[\[ -n "\$\{line\}" \]\]; do/,
    ],
    [
      "runtime environment lines must have a strict uppercase key/value shape",
      /\[\[ "\$\{line\}" =~ \^\(\[A-Z\]\[A-Z0-9_\]\*\)=\(\.\+\)\$ \]\]/,
    ],
    [
      "runtime environment keys must reject duplicates",
      /\[\[ -z "\$\{seen\[\$\{key\}\]:-\}" \]\].*seen\["\$\{key\}"\]=1/s,
    ],
    ["runtime environment values must use explicit assignment", /printf -v "\$\{key\}" '%s' "\$\{value\}"/],
    ["runtime environment keys must be explicitly exported", /export "\$\{key\}"/],
  ]) {
    if (!pattern.test(executable)) violations.push(`${sourcePath}: ${description}`);
  }
  if (
    !executable.includes('validate_environment_value "${key}" "${value}"') &&
    !executable.includes('[[ "${value}" =~ ^[A-Za-z0-9_./:@%+=,-]+$ ]]')
  ) {
    violations.push(`${sourcePath}: runtime environment values must pass the strict safe-character allowlist`);
  }

  const keyCase = /case\s+"\$\{key\}"\s+in([\s\S]*?)^\s*esac\s*$/m.exec(executable)?.[1];
  if (!keyCase) {
    violations.push(`${sourcePath}: runtime environment parser must have an explicit key allowlist`);
  } else {
    const normalized = keyCase.replace(/\\\r?\n/g, "").replace(/\s+/g, "");
    const separator = normalized.indexOf(");;");
    const allowedArm = separator < 0 ? normalized : normalized.slice(0, separator + 3);
    const rejectionArm = separator < 0 ? "" : normalized.slice(separator + 3);
    const expectedArm = `${runtimeEnvironmentKeys.join("|")});;`;
    if (allowedArm !== expectedArm || !/^\*\)die[\s\S]*;;$/.test(rejectionArm)) {
      violations.push(
        `${sourcePath}: runtime environment keys must be exactly ${runtimeEnvironmentKeys.join(", ")} with wildcard rejection`,
      );
    }
  }
}

function inspectHarnessLifecycle(source, sourcePath, kind, violations) {
  inspectRuntimeEnvironmentParser(source, sourcePath, violations);
  const patterns =
    kind === "stack"
      ? [
          [
            "repository identity must match the active checkout",
            /"\$\{MACSAD_REPOSITORY_ROOT\}" == "\$\{REPOSITORY_ROOT\}"/,
          ],
          [
            "runtime root must match the fixed runtime directory",
            /"\$\{MACSAD_RUNTIME_DIR\}" == "\$\{DEFAULT_RUNTIME_DIR\}"/,
          ],
          [
            "secrets root must match the fixed runtime directory",
            /"\$\{MACSAD_SECRETS_DIR\}" == "\$\{DEFAULT_RUNTIME_DIR\}\/secrets"/,
          ],
          [
            "build root must match the runtime directory and exact source revision",
            /"\$\{MACSAD_BUILD_DIR\}" == "\$\{DEFAULT_RUNTIME_DIR\}\/build\/\$\{MACSAD_SOURCE_REVISION\}"/,
          ],
          [
            "source revision must be a full Git object id",
            /"\$\{MACSAD_SOURCE_REVISION\}" =~ \^\[0-9a-f\]\{40\}\$/,
          ],
          [
            "source revision must equal the current checkout HEAD",
            /git -C "\$\{REPOSITORY_ROOT\}" rev-parse --verify HEAD\)" == "\$\{MACSAD_SOURCE_REVISION\}"/,
          ],
        ]
      : [
          [
            "runtime environment path must be fixed inside the checkout",
            /readonly RUNTIME_ENV="\$\{REPOSITORY_ROOT\}\/\.runtime\/compose\/compose\.env"/,
          ],
          [
            "repository identity must match the active checkout",
            /"\$\{MACSAD_REPOSITORY_ROOT\}" == "\$\{REPOSITORY_ROOT\}"/,
          ],
          [
            "runtime root must be fixed inside the checkout",
            /"\$\{MACSAD_RUNTIME_DIR\}" == "\$\{REPOSITORY_ROOT\}\/\.runtime\/compose"/,
          ],
          [
            "secrets root must match the fixed runtime root",
            /"\$\{MACSAD_SECRETS_DIR\}" == "\$\{MACSAD_RUNTIME_DIR\}\/secrets"/,
          ],
          [
            "build root must match the runtime directory and exact source revision",
            /"\$\{MACSAD_BUILD_DIR\}" == "\$\{MACSAD_RUNTIME_DIR\}\/build\/\$\{MACSAD_SOURCE_REVISION\}"/,
          ],
          [
            "source revision must be a full Git object id",
            /"\$\{MACSAD_SOURCE_REVISION\}" =~ \^\[0-9a-f\]\{40\}\$/,
          ],
          [
            "source revision must equal the current checkout HEAD",
            /git -C "\$\{REPOSITORY_ROOT\}" rev-parse --verify HEAD\)" == "\$\{MACSAD_SOURCE_REVISION\}"/,
          ],
        ];
  for (const [description, pattern] of patterns) {
    if (!pattern.test(source)) violations.push(`${sourcePath}: ${description}`);
  }

  if (/--untracked-files(?:=|\s+)no\b/.test(source)) {
    violations.push(`${sourcePath}: deployment cleanliness may not hide untracked files`);
  }
  const fullStatusChecks = source.match(
    /git -C "\$\{REPOSITORY_ROOT\}" status --porcelain(?:[\s"')]|$)/g,
  ) ?? [];
  const requiredChecks = kind === "stack" ? 2 : 1;
  if (fullStatusChecks.length < requiredChecks) {
    violations.push(
      `${sourcePath}: expected at least ${requiredChecks} full tracked-and-untracked Git cleanliness check(s)`,
    );
  }
}

export function validateRepository(repositoryRoot = defaultRepositoryRoot) {
  const root = resolve(repositoryRoot);
  const composePath = join(root, "ops", "compose", "compose.yaml");
  if (!existsSync(composePath)) {
    throw new ComposeGuardrailError(["ops/compose/compose.yaml: required Compose file is missing"]);
  }
  const result = inspectComposeSource(readFileSync(composePath, "utf8"), {
    repositoryRoot: root,
    sourcePath: composePath,
  });
  if (!result.pgadminConfigFile) {
    throw new ComposeGuardrailError(["ops/compose/compose.yaml: pgAdmin servers config is unresolved"]);
  }
  const configPath = resolve(dirname(composePath), result.pgadminConfigFile);
  const relativeConfig = relative(root, configPath);
  if (relativeConfig.startsWith(`..${sep}`) || isAbsolute(relativeConfig)) {
    throw new ComposeGuardrailError([
      "ops/compose/compose.yaml: pgAdmin servers config must stay inside the repository",
    ]);
  }
  if (!existsSync(configPath) || !lstatSync(configPath).isFile() || lstatSync(configPath).isSymbolicLink()) {
    throw new ComposeGuardrailError([
      `${repositoryLabel(configPath, root)}: pgAdmin servers config must be a regular, non-symlink file`,
    ]);
  }
  inspectPgAdminServers(readFileSync(configPath, "utf8"), {
    sourcePath: repositoryLabel(configPath, root),
  });

  const lifecycleViolations = [];
  const ignorePath = join(root, ".gitignore");
  const ignore = existsSync(ignorePath) ? readFileSync(ignorePath, "utf8") : "";
  if (!/^\.runtime\/\s*$/m.test(ignore)) {
    lifecycleViolations.push(".gitignore: .runtime/ must be ignored at the repository root");
  }
  const stackPath = join(root, "ops", "compose", "stack.sh");
  const stack = existsSync(stackPath) ? readFileSync(stackPath, "utf8") : "";
  const devPath = join(root, "scripts", "dev.sh");
  const dev = existsSync(devPath) ? readFileSync(devPath, "utf8") : "";
  if (!existsSync(stackPath)) lifecycleViolations.push("ops/compose/stack.sh: required harness is missing");
  if (!existsSync(devPath)) lifecycleViolations.push("scripts/dev.sh: required harness is missing");
  for (const [description, pattern] of [
    [
      "runtime root must be fixed beneath ignored .runtime/compose",
      /readonly DEFAULT_RUNTIME_DIR="\$\{REPOSITORY_ROOT\}\/\.runtime\/compose"/,
    ],
    ["secret files must be rooted beneath the runtime directory", /secrets_dir="\$\{root_runtime\}\/secrets"/],
    [
      "build inputs must be revision-scoped beneath the runtime directory",
      /build_dir="\$\{root_runtime\}\/build\/\$\{source_revision\}"/,
    ],
    [
      "runtime override must be rejected unless it equals the fixed runtime root",
      /\[\[ -n "\$\{MACSAD_RUNTIME_DIR:-\}" && "\$\{MACSAD_RUNTIME_DIR\}" != "\$\{DEFAULT_RUNTIME_DIR\}" \]\]/,
    ],
    ["runtime resolver must return only the fixed runtime root", /printf '%s' "\$\{DEFAULT_RUNTIME_DIR\}"/],
    ["generated environment must require the build directory", /MACSAD_BUILD_DIR/],
    ["generated environment must require the secrets directory", /MACSAD_SECRETS_DIR/],
    [
      "bind address must be verified as this host's Tailnet IPv4",
      /tailscale ip -4\s*\|\s*grep -Fqx -- "\$\{bind_ip\}"/,
    ],
    [
      "wildcard and loopback addresses must be rejected",
      /"\$\{bind_ip\}" != '0\.0\.0\.0'.*"\$\{bind_ip\}" != 127\.\*/s,
    ],
    ["the local LOGOS toolchain must pass its locked verifier", /scripts\/logos\.sh" --version/],
    [
      "the verified local largo binary must be staged",
      /target\/debug\/largo" "\$\{stage\}\/logos-runtime\/largo"/,
    ],
  ]) {
    if (!pattern.test(stack)) lifecycleViolations.push(`ops/compose/stack.sh: ${description}`);
  }
  inspectHarnessLifecycle(stack, "ops/compose/stack.sh", "stack", lifecycleViolations);
  inspectHarnessLifecycle(dev, "scripts/dev.sh", "dev", lifecycleViolations);
  if (lifecycleViolations.length > 0) throw new ComposeGuardrailError(lifecycleViolations);

  const deployViolations = [];
  for (const path of readDeployFiles(join(root, "ops", "compose"))) {
    if (resolve(path) === resolve(composePath) || resolve(path) === resolve(configPath)) continue;
    const text = readFileSync(path, "utf8");
    const label = repositoryLabel(path, root);
    if (hasForbiddenGetMutation(text)) {
      deployViolations.push(`${label}: GET may not be used for a mutation or command route`);
    }
    if (/(?:\/var\/run\/(?:docker|podman)\.sock|docker_engine(?:\.sock)?|\bDOCKER_HOST\b)/i.test(text)) {
      deployViolations.push(`${label}: Docker socket access is forbidden`);
    }
    if (/crates\.io/i.test(text)) {
      deployViolations.push(`${label}: deploy files may not resolve LOGOS from a registry`);
    }
    for (const match of text.matchAll(/^\s*FROM\s+([^\s]+)(?:\s+AS\s+\S+)?\s*$/gim)) {
      if (!pinnedImagePattern.test(match[1])) {
        deployViolations.push(`${label}: Dockerfile base image is not tag-and-digest pinned: ${match[1]}`);
      }
    }
  }
  if (deployViolations.length > 0) throw new ComposeGuardrailError(deployViolations);
  return result;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const result = validateRepository();
    process.stdout.write(
      `compose guardrails passed (${result.services.length} services, staged build root ${result.stagedRuntimeRoot})\n`,
    );
  } catch (error) {
    if (error instanceof ComposeGuardrailError) {
      process.stderr.write(`${error.message}\n`);
      process.exitCode = 1;
    } else {
      throw error;
    }
  }
}
