import assert from "node:assert/strict";
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  realpathSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, sep } from "node:path";
import test from "node:test";
import {
  defaultPolicyPath,
  lintLogosSources,
  loadSourcePolicy,
} from "../../scripts/logos-source-lint.mjs";

const temporaryBase = realpathSync(tmpdir());

function basePolicy(overrides = {}) {
  const policy = {
    $schema: "../schemas/logos-source-quality-v1.schema.json",
    schema: "macsad-logos-source-quality/1",
    files: {
      maxPhysicalLines: 120,
      maxLogicalLinesPerDefinition: 80,
      maxLineLength: 220,
    },
    scopedCss: {
      preferredMaxLineLength: 1200,
      hardMaxLineLength: 4600,
      duplicateMinimumDeclarations: 8,
      maximumIdenticalOccurrences: 1,
    },
    duplicateBlocks: {
      minimumStatements: 6,
      minimumBehaviorStatements: 2,
      maximumOccurrences: 1,
    },
    markers: [
      {
        id: "unfinished-work",
        pattern: "\\b(?:TODO|FIXME|TBD|TBC|CHANGEME)\\b",
        flags: "i",
      },
      { id: "unsafe-workaround", pattern: "\\b(?:HACK|XXX)\\b", flags: "" },
      { id: "placeholder-sentinel", pattern: "\\bPLACEHOLDER\\b", flags: "" },
      { id: "lorem-ipsum", pattern: "\\blorem\\s+ipsum\\b", flags: "i" },
    ],
    debt: [],
  };
  for (const [section, values] of Object.entries(overrides)) {
    if (
      values &&
      typeof values === "object" &&
      !Array.isArray(values) &&
      policy[section] &&
      typeof policy[section] === "object" &&
      !Array.isArray(policy[section])
    ) {
      policy[section] = { ...policy[section], ...values };
    } else {
      policy[section] = values;
    }
  }
  return policy;
}

function write(path, contents) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, contents, "utf8");
}

function fixture({ files = {}, policy = basePolicy(), moduleManifest = null } = {}) {
  const root = mkdtempSync(join(temporaryBase, "macsad-logos-lint-"));
  for (const [portablePath, contents] of Object.entries(files)) {
    write(join(root, ...portablePath.split("/")), contents);
  }
  if (Object.keys(files).length === 0) {
    write(
      join(root, "logos", "fixture", "src", "main.lg"),
      "# Fixture\n\n## To value () -> Int:\n    Return 1.\n",
    );
  }
  const policyPath = join(root, ".macsad", "policies", "logos-source-quality.json");
  write(policyPath, `${JSON.stringify(policy, null, 2)}\n`);
  const moduleManifestPath = join(root, "tests", "logos-module-manifest.json");
  if (moduleManifest) write(moduleManifestPath, `${JSON.stringify(moduleManifest, null, 2)}\n`);
  return { moduleManifestPath, policyPath, root };
}

function removeFixture(root) {
  const canonical = realpathSync(root);
  if (!canonical.startsWith(`${temporaryBase}${sep}macsad-logos-lint-`)) {
    throw new Error(`refusing to remove unexpected fixture: ${canonical}`);
  }
  rmSync(canonical, { recursive: true });
}

function runFixture(created, options = {}) {
  return lintLogosSources({
    root: created.root,
    policyPath: created.policyPath,
    moduleManifestPath: created.moduleManifestPath,
    checkModuleGraph: false,
    ...options,
  });
}

function rules(result) {
  return result.failures.map(({ rule }) => rule);
}

test("the checked-in policy is exact and the repository baseline is admitted only as debt", () => {
  const policy = loadSourcePolicy();
  assert.equal(policy.$schema, "../schemas/logos-source-quality-v1.schema.json");
  const checkedInSchema = JSON.parse(
    readFileSync(join(dirname(defaultPolicyPath), policy.$schema), "utf8"),
  );
  assert.equal(checkedInSchema.$schema, "https://json-schema.org/draft/2020-12/schema");
  assert.equal(
    checkedInSchema.properties.$schema.const,
    "../schemas/logos-source-quality-v1.schema.json",
  );
  assert.deepEqual(policy.files, {
    maxPhysicalLines: 120,
    maxLogicalLinesPerDefinition: 80,
    maxLineLength: 220,
  });
  assert.deepEqual(policy.scopedCss, {
    preferredMaxLineLength: 1200,
    hardMaxLineLength: 4600,
    duplicateMinimumDeclarations: 8,
    maximumIdenticalOccurrences: 1,
  });
  assert.deepEqual(policy.duplicateBlocks, {
    minimumStatements: 6,
    minimumBehaviorStatements: 2,
    maximumOccurrences: 1,
  });
  assert.deepEqual(policy.markers, [
    {
      id: "unfinished-work",
      pattern: "\\b(?:TODO|FIXME|TBD|TBC|CHANGEME)\\b",
      flags: "i",
    },
    {
      id: "unsafe-workaround",
      pattern: "\\b(?:HACK|XXX)\\b",
      flags: "",
    },
    {
      id: "placeholder-sentinel",
      pattern: "\\bPLACEHOLDER\\b",
      flags: "",
    },
    {
      id: "lorem-ipsum",
      pattern: "\\blorem\\s+ipsum\\b",
      flags: "i",
    },
  ]);
  assert.deepEqual(
    policy.debt.map(({ rule, fingerprint, locations, removalCondition }) => ({
      rule,
      fingerprint,
      locations,
      removalCondition,
    })),
    [
      {
        rule: "scoped-css-preferred-length",
        fingerprint: "2203aa427bb0f1098bf1352a312e82e837bbb615f49f8056d11a099970733344",
        locations: ["logos/admin/src/admin_app.lg:13"],
        removalCondition:
          "Split navigation and shell layout into cohesive imported Components before this exact CSS string receives any product change.",
      },
      {
        rule: "scoped-css-preferred-length",
        fingerprint: "cb03a1de16b4f14d5911e5e7b5ab388b528d3008de161c3ef89f7060e297e2aa",
        locations: ["logos/admin/src/board_workspace.lg:16"],
        removalCondition:
          "Extract the metrics, draft form, and board lanes into responsibility-owned imported Components before modifying this CSS.",
      },
      {
        rule: "duplicate-scoped-css",
        fingerprint: "2297746d7c4c40121b0f3f3e8a73a2d24500e43bedd36cd8bacba86980ec9335",
        locations: [
          "logos/admin/src/read_only_panels.lg:8",
          "logos/admin/src/read_only_panels.lg:17",
          "logos/admin/src/read_only_panels.lg:26",
        ],
        removalCondition:
          "Replace the copies only after LOGOS provides tested shared scoped styles or the panels become one parameterized Component.",
      },
      {
        rule: "scoped-css-preferred-length",
        fingerprint: "5b0df9be2bf60d3653449636bfa2bf2f8061414f43a819198ba46ba5bfce9429",
        locations: ["logos/public-site/src/research_ledger.lg:13"],
        removalCondition:
          "Extract the section heading, publication cards, and pipeline rail into imported Components before changing this exact CSS.",
      },
    ],
  );
  const result = lintLogosSources();
  assert.deepEqual(result.failures, []);
  assert.equal(result.filesChecked, 16);
  assert.deepEqual(
    result.activeDebt.map(({ rule }) => rule).sort(),
    [
      "duplicate-scoped-css",
      "scoped-css-preferred-length",
      "scoped-css-preferred-length",
      "scoped-css-preferred-length",
    ],
  );
});

test("physical line threshold is exact and tells the author to split the module", async (context) => {
  const policy = basePolicy({
    files: { maxPhysicalLines: 20, maxLogicalLinesPerDefinition: 20 },
  });
  await context.test("twenty lines pass", () => {
    const lines = ["# Fixture", "", "## To value () -> Int:"];
    while (lines.length < 20) lines.push(`    Let value${lines.length} be ${lines.length}.`);
    const created = fixture({ files: { "logos/fixture/src/main.lg": lines.join("\n") }, policy });
    try {
      assert(!rules(runFixture(created)).includes("max-physical-lines"));
    } finally {
      removeFixture(created.root);
    }
  });
  await context.test("twenty-one lines fail", () => {
    const lines = ["# Fixture", "", "## To value () -> Int:"];
    while (lines.length < 21) lines.push(`    Let value${lines.length} be ${lines.length}.`);
    const created = fixture({ files: { "logos/fixture/src/main.lg": lines.join("\n") }, policy });
    try {
      const failure = runFixture(created).failures.find(
        ({ rule }) => rule === "max-physical-lines",
      );
      assert.match(failure.message, /split the module at a responsibility boundary/);
    } finally {
      removeFixture(created.root);
    }
  });
});

test("logical definition threshold is exact and excludes blank/comment lines", async (context) => {
  const policy = basePolicy({
    files: { maxPhysicalLines: 30, maxLogicalLinesPerDefinition: 5 },
  });
  await context.test("five logical lines pass", () => {
    const created = fixture({
      files: {
        "logos/fixture/src/main.lg":
          "# Fixture\n\n## To value () -> Int:\n    # explanation\n\n    Let one be 1.\n    Let two be 2.\n    Return one.\n    \n",
      },
      policy,
    });
    try {
      assert(!rules(runFixture(created)).includes("max-logical-lines-per-definition"));
    } finally {
      removeFixture(created.root);
    }
  });
  await context.test("six logical lines fail with an extraction seam", () => {
    const created = fixture({
      files: {
        "logos/fixture/src/main.lg":
          "# Fixture\n\n## To value () -> Int:\n    Let one be 1.\n    Let two be 2.\n    Let three be 3.\n    Let four be 4.\n    Return one.\n",
      },
      policy,
    });
    try {
      const failure = runFixture(created).failures.find(
        ({ rule }) => rule === "max-logical-lines-per-definition",
      );
      assert.match(failure.message, /## To helper|child ## Component/);
    } finally {
      removeFixture(created.root);
    }
  });
});

test("ordinary and scoped-CSS line limits are distinct hard contracts", async (context) => {
  const policy = basePolicy({
    files: { maxLineLength: 80 },
    scopedCss: { preferredMaxLineLength: 100, hardMaxLineLength: 200 },
  });
  await context.test("an ordinary 81-character line fails", () => {
    const line = `    Return "${"x".repeat(67)}".`;
    assert.equal(line.length, 81);
    const created = fixture({
      files: { "logos/fixture/src/main.lg": `# Fixture\n\n## To value () -> Text:\n${line}\n` },
      policy,
    });
    try {
      assert(rules(runFixture(created)).includes("max-line-length"));
    } finally {
      removeFixture(created.root);
    }
  });
  await context.test("scoped CSS may cross the ordinary limit but not its hard cap", () => {
    const css = `    css ".panel { ${"color: red; ".repeat(20)} }"`;
    assert(css.length > 200);
    const created = fixture({
      files: {
        "logos/fixture/src/main.lg": `# Fixture\n\n## Component Panel:\n    View:\n${css}\n        div: "ok"\n`,
      },
      policy,
    });
    try {
      const result = runFixture(created);
      assert(rules(result).includes("scoped-css-hard-length"));
      assert(!rules(result).includes("max-line-length"));
    } finally {
      removeFixture(created.root);
    }
  });
});

test("scoped-CSS design debt is content and location fingerprinted", () => {
  const policy = basePolicy({
    files: { maxLineLength: 80 },
    scopedCss: { preferredMaxLineLength: 100, hardMaxLineLength: 500 },
  });
  const css = `    css ".panel { ${"color: red; ".repeat(10)} }"`;
  const source = `# Fixture\n\n## Component Panel:\n    View:\n${css}\n        div: "ok"\n`;
  const created = fixture({ files: { "logos/fixture/src/main.lg": source }, policy });
  try {
    const initial = runFixture(created);
    const issue = initial.failures.find(
      ({ rule }) => rule === "scoped-css-preferred-length",
    );
    assert(issue);
    policy.debt = [
      {
        rule: issue.rule,
        fingerprint: issue.fingerprint,
        locations: issue.locations,
        reason: "This exact fixture models reviewed scoped style debt before a safe component split exists.",
        removalCondition: "Remove it after extracting the exact style into a semantics-preserving child Component.",
      },
    ];
    write(created.policyPath, `${JSON.stringify(policy, null, 2)}\n`);
    const admitted = runFixture(created);
    assert.deepEqual(admitted.failures, []);
    assert.equal(admitted.activeDebt.length, 1);

    write(
      join(created.root, "logos", "fixture", "src", "main.lg"),
      `${source}\n## Component Copy:\n    View:\n${css}\n        div: "copy"\n`,
    );
    const copied = runFixture(created);
    assert(rules(copied).includes("scoped-css-preferred-length"));
    assert(rules(copied).includes("duplicate-scoped-css"));

    write(
      join(created.root, "logos", "fixture", "src", "main.lg"),
      source.replace("color: red", "color: blue"),
    );
    const changed = runFixture(created);
    assert(rules(changed).includes("stale-source-debt"));
    assert(rules(changed).includes("scoped-css-preferred-length"));
  } finally {
    removeFixture(created.root);
  }
});

test("large identical scoped CSS fails at exactly the declaration threshold", async (context) => {
  function twoComponents(declarations) {
    const css = `.panel { ${Array.from({ length: declarations }, (_, index) => `p${index}: v${index};`).join(" ")} }`;
    return (
      `# Fixture\n\n## Component One:\n    View:\n        css "${css}"\n        div: "one"\n\n` +
      `## Component Two:\n    View:\n        css "${css}"\n        div: "two"\n`
    );
  }
  await context.test("seven declarations are below the duplicate threshold", () => {
    const created = fixture({
      files: { "logos/fixture/src/main.lg": twoComponents(7) },
    });
    try {
      assert(!rules(runFixture(created)).includes("duplicate-scoped-css"));
    } finally {
      removeFixture(created.root);
    }
  });
  await context.test("eight declarations fail", () => {
    const created = fixture({
      files: { "logos/fixture/src/main.lg": twoComponents(8) },
    });
    try {
      const failure = runFixture(created).failures.find(
        ({ rule }) => rule === "duplicate-scoped-css",
      );
      assert.equal(failure.locations.length, 2);
      assert.match(failure.message, /same scoped-CSS block appears 2 times/);
    } finally {
      removeFixture(created.root);
    }
  });
  await context.test("raw scoped-CSS literals cannot bypass duplicate analysis", () => {
    const source = twoComponents(8).replaceAll('css "', 'css r"');
    const created = fixture({ files: { "logos/fixture/src/main.lg": source } });
    try {
      assert(rules(runFixture(created)).includes("duplicate-scoped-css"));
    } finally {
      removeFixture(created.root);
    }
  });
  await context.test("inline comments after CSS are erased without consuming color hashes", () => {
    const declarations = Array.from(
      { length: 8 },
      (_, index) => `p${index}: v${index};`,
    ).join(" ");
    const css = `.panel { color: #fff; ${declarations} }`;
    const source =
      `# Fixture\n\n## Component One:\n    View:\n        css "${css}" # first style\n` +
      "        div: \"one\"\n\n" +
      `## Component Two:\n    View:\n        css "${css}" # second style\n` +
      "        div: \"two\"\n";
    const created = fixture({ files: { "logos/fixture/src/main.lg": source } });
    try {
      assert(rules(runFixture(created)).includes("duplicate-scoped-css"));
    } finally {
      removeFixture(created.root);
    }
  });
  await context.test("CSS block comments cannot change an otherwise identical fingerprint", () => {
    const declarations = Array.from(
      { length: 8 },
      (_, index) => `p${index}: v${index};`,
    ).join(" ");
    const first = `.panel { /* first review */ ${declarations} }`;
    const second = `.panel { /* unrelated wording */ ${declarations} }`;
    const source =
      `# Fixture\n\n## Component One:\n    View:\n        css "${first}"\n` +
      "        div: \"one\"\n\n" +
      `## Component Two:\n    View:\n        css "${second}"\n` +
      "        div: \"two\"\n";
    const created = fixture({ files: { "logos/fixture/src/main.lg": source } });
    try {
      assert(rules(runFixture(created)).includes("duplicate-scoped-css"));
    } finally {
      removeFixture(created.root);
    }
  });
  await context.test("CSS comment-looking text inside escaped strings remains semantic", () => {
    const declarations = Array.from(
      { length: 8 },
      (_, index) => `p${index}: v${index};`,
    ).join(" ");
    const first = `.panel { content: \\"/* first */\\"; ${declarations} }`;
    const second = `.panel { content: \\"/* second */\\"; ${declarations} }`;
    const source =
      `# Fixture\n\n## Component One:\n    View:\n        css "${first}"\n` +
      "        div: \"one\"\n\n" +
      `## Component Two:\n    View:\n        css "${second}"\n` +
      "        div: \"two\"\n";
    const created = fixture({ files: { "logos/fixture/src/main.lg": source } });
    try {
      assert(!rules(runFixture(created)).includes("duplicate-scoped-css"));
    } finally {
      removeFixture(created.root);
    }
  });
  await context.test("semicolons inside CSS strings and comments do not meet the threshold", () => {
    const css = '.panel { content: \\";;;;;;;;\\"; /* ;;;;;;;; */ color: red; }';
    const source =
      `# Fixture\n\n## Component One:\n    View:\n        css "${css}"\n` +
      "        div: \"one\"\n\n" +
      `## Component Two:\n    View:\n        css "${css}"\n` +
      "        div: \"two\"\n";
    const created = fixture({ files: { "logos/fixture/src/main.lg": source } });
    try {
      assert(!rules(runFixture(created)).includes("duplicate-scoped-css"));
    } finally {
      removeFixture(created.root);
    }
  });
  await context.test("CSS double-quoted literal whitespace remains semantic", () => {
    const declarations = Array.from(
      { length: 8 },
      (_, index) => `p${index}: v${index};`,
    ).join(" ");
    const first = `.panel { content: \\"a  b\\"; ${declarations} }`;
    const second = `.panel { content: \\"a b\\"; ${declarations} }`;
    const source =
      `# Fixture\n\n## Component One:\n    View:\n        css "${first}"\n        div: "one"\n\n` +
      `## Component Two:\n    View:\n        css "${second}"\n        div: "two"\n`;
    const created = fixture({ files: { "logos/fixture/src/main.lg": source } });
    try {
      assert(!rules(runFixture(created)).includes("duplicate-scoped-css"));
    } finally {
      removeFixture(created.root);
    }
  });
  function tripleCssComponent(
    name,
    {
      raw = false,
      mutation = "",
      selector = ".panel",
      closingComment = "",
      cssComment = "",
    } = {},
  ) {
    const declarations = Array.from(
      { length: 8 },
      (_, index) => `                p${index}: ${index === 7 && mutation ? mutation : `v${index}`};`,
    ).join("\n");
    return (
      `## Component ${name}:\n` +
      "    View:\n" +
      `        css ${raw ? "r" : ""}\"\"\"\n` +
      `            ${selector} {\n` +
      (cssComment ? `                /* ${cssComment} */\n` : "") +
      `${declarations}\n` +
      "            }\n" +
      `        \"\"\"${closingComment ? ` # ${closingComment}` : ""}\n` +
      `        div: \"${name}\"\n`
    );
  }
  await context.test("eight declarations in triple-quoted CSS fail on a second copy", () => {
    const source =
      `# Fixture\n\n${tripleCssComponent("One")}\n` +
      tripleCssComponent("Two");
    const created = fixture({ files: { "logos/fixture/src/main.lg": source } });
    try {
      const failure = runFixture(created).failures.find(
        ({ rule }) => rule === "duplicate-scoped-css",
      );
      assert.equal(failure.locations.length, 2);
      assert.deepEqual(failure.locations, [
        "logos/fixture/src/main.lg:5",
        "logos/fixture/src/main.lg:21",
      ]);
    } finally {
      removeFixture(created.root);
    }
  });
  await context.test("a triple-quoted CSS mutation changes its identity", () => {
    const source =
      `# Fixture\n\n${tripleCssComponent("One")}\n` +
      tripleCssComponent("Two", { mutation: "changed" });
    const created = fixture({ files: { "logos/fixture/src/main.lg": source } });
    try {
      assert(!rules(runFixture(created)).includes("duplicate-scoped-css"));
    } finally {
      removeFixture(created.root);
    }
  });
  await context.test("raw and plain triple-quoted CSS share duplicate analysis", () => {
    const source =
      `# Fixture\n\n${tripleCssComponent("One", { raw: true })}\n` +
      tripleCssComponent("Two");
    const created = fixture({ files: { "logos/fixture/src/main.lg": source } });
    try {
      assert(rules(runFixture(created)).includes("duplicate-scoped-css"));
    } finally {
      removeFixture(created.root);
    }
  });
  await context.test("comments after triple-CSS closers are not malformed tokens", () => {
    const source =
      `# Fixture\n\n${tripleCssComponent("One", { closingComment: "first style" })}\n` +
      tripleCssComponent("Two", { closingComment: "second style" });
    const created = fixture({ files: { "logos/fixture/src/main.lg": source } });
    try {
      const result = runFixture(created);
      assert(rules(result).includes("duplicate-scoped-css"));
      assert(!rules(result).includes("malformed-triple-css"));
    } finally {
      removeFixture(created.root);
    }
  });
  await context.test("raw and plain triple CSS ignore CSS comment wording", () => {
    const source =
      `# Fixture\n\n${tripleCssComponent("One", { raw: true, cssComment: "first" })}\n` +
      tripleCssComponent("Two", { cssComment: "second" });
    const created = fixture({ files: { "logos/fixture/src/main.lg": source } });
    try {
      assert(rules(runFixture(created)).includes("duplicate-scoped-css"));
    } finally {
      removeFixture(created.root);
    }
  });
  await context.test("triple CSS preserves whitespace inside actual double-quoted strings", () => {
    const declarations = Array.from(
      { length: 8 },
      (_, index) => `                p${index}: v${index};`,
    ).join("\n");
    function component(name, content, raw = false) {
      return (
        `## Component ${name}:\n    View:\n        css ${raw ? "r" : ""}\"\"\"\n` +
        "            .panel {\n" +
        `                content: "${content}";\n` +
        `${declarations}\n` +
        "            }\n        \"\"\"\n" +
        `        div: "${name}"\n`
      );
    }
    const source =
      `# Fixture\n\n${component("One", "a  b", true)}\n` +
      component("Two", "a b");
    const created = fixture({ files: { "logos/fixture/src/main.lg": source } });
    try {
      assert(!rules(runFixture(created)).includes("duplicate-scoped-css"));
    } finally {
      removeFixture(created.root);
    }
  });
  await context.test("unterminated CSS comments fail explicitly", () => {
    const source =
      "# Fixture\n\n## Component Broken:\n    View:\n" +
      '        css ".panel { color: red; /* never closed"\n' +
      '        div: "broken"\n';
    const created = fixture({ files: { "logos/fixture/src/main.lg": source } });
    try {
      const failure = runFixture(created).failures.find(
        ({ rule }) => rule === "unterminated-css-comment",
      );
      assert.match(failure.message, /close it before CSS is normalized or compared/);
    } finally {
      removeFixture(created.root);
    }
  });
});

const behaviorBlock = [
  "    Let draft be a signal \"\".",
  "    button:",
  "        on click:",
  "            Set draft to \"ready\".",
  "            Call recordDraft with draft.",
  "        span: \"Stage\"",
];

test("six normalized behavior-bearing statements copied across files fail", () => {
  const created = fixture({
    files: {
      "logos/fixture/src/one.lg": `# One\n\n## Component One:\n${behaviorBlock.join("\n")}\n`,
      "logos/fixture/src/two.lg":
        `# Two\n\n## Component Two:\n` +
        behaviorBlock.map((line) => line.replace(/^ {4}/, "        ")).join("\n") +
        "\n",
    },
  });
  try {
    const failure = runFixture(created).failures.find(
      ({ rule }) => rule === "duplicate-statement-block",
    );
    assert.equal(failure.locations.length, 2);
    assert.match(failure.message, /6 normalized statements/);
    assert.match(failure.message, /## To policy helper/);
  } finally {
    removeFixture(created.root);
  }
});

test("inline comments cannot hide copied behavior", async (context) => {
  function commented(block, commentFor) {
    return block.map((line, index) => `${line} # ${commentFor(index)}`);
  }

  await context.test("matching comments are erased before behavior classification", () => {
    const block = commented(behaviorBlock, () => "reviewed");
    const created = fixture({
      files: {
        "logos/fixture/src/main.lg":
          `# Fixture\n\n## Component One:\n${block.join("\n")}\n\n` +
          `## Component Two:\n${block.join("\n")}\n`,
      },
    });
    try {
      assert(rules(runFixture(created)).includes("duplicate-statement-block"));
    } finally {
      removeFixture(created.root);
    }
  });

  await context.test("different comments are erased before token comparison", () => {
    const first = commented(behaviorBlock, (index) => `first-${index}`);
    const second = commented(behaviorBlock, (index) => `second-${index}`);
    const created = fixture({
      files: {
        "logos/fixture/src/main.lg":
          `# Fixture\n\n## Component One:\n${first.join("\n")}\n\n` +
          `## Component Two:\n${second.join("\n")}\n`,
      },
    });
    try {
      assert(rules(runFixture(created)).includes("duplicate-statement-block"));
    } finally {
      removeFixture(created.root);
    }
  });
});

test("hash characters inside ordinary strings remain semantic", () => {
  const first = behaviorBlock.map((line) =>
    line.replace('span: "Stage"', 'span: "Stage # alpha"'),
  );
  const second = behaviorBlock.map((line) =>
    line.replace('span: "Stage"', 'span: "Stage # beta"'),
  );
  const created = fixture({
    files: {
      "logos/fixture/src/main.lg":
        `# Fixture\n\n## Component One:\n${first.join("\n")}\n\n` +
        `## Component Two:\n${second.join("\n")}\n`,
    },
  });
  try {
    assert(!rules(runFixture(created)).includes("duplicate-statement-block"));
  } finally {
    removeFixture(created.root);
  }
});

test("inline-comment lexing matches raw strings and character literals", async (context) => {
  const staticTail = [
    '    div: "one"',
    '    span: "two"',
    '    p: "three"',
    '    strong: "four"',
  ];
  function block(first, second) {
    return [first, second, ...staticTail];
  }
  function duplicateResult(first, second) {
    const created = fixture({
      files: {
        "logos/fixture/src/main.lg":
          `# Fixture\n\n## Component One:\n${first.join("\n")}\n\n` +
          `## Component Two:\n${second.join("\n")}\n`,
      },
    });
    try {
      return rules(runFixture(created)).includes("duplicate-statement-block");
    } finally {
      removeFixture(created.root);
    }
  }

  await context.test("hash character literals remain code before comments", () => {
    const first = block(
      "    Set marker to `#`. # first marker",
      "    Set backup to `#`. # first backup",
    );
    const second = block(
      "    Set marker to `#`. # second marker",
      "    Set backup to `#`. # second backup",
    );
    assert(duplicateResult(first, second));
  });
  await context.test("different character literals remain different tokens", () => {
    const first = block("    Set marker to `#`.", "    Set backup to `#`.");
    const second = block("    Set marker to `@`.", "    Set backup to `@`.");
    assert(!duplicateResult(first, second));
  });
  await context.test("whitespace character literals are not collapsed", () => {
    const spaces = block("    Set marker to ` `.", "    Set backup to ` `.");
    const tabs = block("    Set marker to `\t`.", "    Set backup to `\t`.");
    assert(!duplicateResult(spaces, tabs));
  });
  await context.test("raw-string closing quotes expose following comments", () => {
    const first = block(
      '    Set path to r"C:\\". # first path',
      '    Set mirror to r"D:\\". # first mirror',
    );
    const second = block(
      '    Set path to r"C:\\". # second path',
      '    Set mirror to r"D:\\". # second mirror',
    );
    assert(duplicateResult(first, second));
  });
});

test("copied behavior is also detected within one file", () => {
  const created = fixture({
    files: {
      "logos/fixture/src/main.lg":
        `# Fixture\n\n## Component One:\n${behaviorBlock.join("\n")}\n\n` +
        `## Component Two:\n${behaviorBlock.join("\n")}\n`,
    },
  });
  try {
    const failure = runFixture(created).failures.find(
      ({ rule }) => rule === "duplicate-statement-block",
    );
    assert.equal(failure.locations.length, 2);
    assert(failure.locations.every((location) => location.startsWith("logos/fixture/src/main.lg:")));
  } finally {
    removeFixture(created.root);
  }
});

test("LOGOS imperatives do not evade behavior-bearing duplicate detection", () => {
  const imperativeBlock = [
    "    button:",
    "        on click:",
    "            Increase count.",
    "        span: \"Increment\"",
    "    p: \"Counter control\"",
    "    div [class=\"boundary\"]: \"Local only\"",
  ];
  const created = fixture({
    files: {
      "logos/fixture/src/main.lg":
        `# Fixture\n\n## Component One:\n${imperativeBlock.join("\n")}\n\n` +
        `## Component Two:\n${imperativeBlock.join("\n")}\n`,
    },
  });
  try {
    assert(rules(runFixture(created)).includes("duplicate-statement-block"));
  } finally {
    removeFixture(created.root);
  }
});

test("five copied statements remain below the exact block threshold", () => {
  const shortBlock = behaviorBlock.slice(0, 5);
  const created = fixture({
    files: {
      "logos/fixture/src/main.lg":
        `# Fixture\n\n## Component One:\n${shortBlock.join("\n")}\n\n` +
        `## Component Two:\n${shortBlock.join("\n")}\n`,
    },
  });
  try {
    assert(!rules(runFixture(created)).includes("duplicate-statement-block"));
  } finally {
    removeFixture(created.root);
  }
});

test("normalization preserves literal whitespace instead of inventing a copy", () => {
  const secondBlock = behaviorBlock.map((line) =>
    line.replace('span: "Stage"', 'span: "Stage  now"'),
  );
  const created = fixture({
    files: {
      "logos/fixture/src/main.lg":
        `# Fixture\n\n## Component One:\n${behaviorBlock.join("\n")}\n\n` +
        `## Component Two:\n${secondBlock.join("\n")}\n`,
    },
  });
  try {
    assert(!rules(runFixture(created)).includes("duplicate-statement-block"));
  } finally {
    removeFixture(created.root);
  }
});

test("scoped CSS is a duplicate-block boundary and cannot stitch separate actions", () => {
  const declarations = (prefix) =>
    Array.from({ length: 8 }, (_, index) => `${prefix}${index}: v${index};`).join(" ");
  const source =
    "# Fixture\n\n## Component One:\n" +
    "    Let draft be a signal \"\".\n" +
    "    button:\n" +
    "        on click:\n" +
    `            css ".one { ${declarations("a")} }"\n` +
    "            Set draft to \"ready\".\n" +
    "            Call recordDraft with draft.\n" +
    "        span: \"Stage\"\n\n" +
    "## Component Two:\n" +
    "    Let draft be a signal \"\".\n" +
    "    button:\n" +
    "        on click:\n" +
    `            css ".two { ${declarations("b")} }"\n` +
    "            Set draft to \"ready\".\n" +
    "            Call recordDraft with draft.\n" +
    "        span: \"Stage\"\n";
  const created = fixture({ files: { "logos/fixture/src/main.lg": source } });
  try {
    assert(!rules(runFixture(created)).includes("duplicate-statement-block"));
  } finally {
    removeFixture(created.root);
  }
});

test("triple-quoted scoped CSS forms one boundary without swallowing later behavior", async (context) => {
  function tripleCss(selector, propertyPrefix) {
    const declarations = Array.from(
      { length: 8 },
      (_, index) => `                ${propertyPrefix}${index}: v${index};`,
    ).join("\n");
    return (
      "            css \"\"\"\n" +
      `                ${selector} {\n` +
      `${declarations}\n` +
      "                }\n" +
      "            \"\"\"\n"
    );
  }
  function component(name, selector, propertyPrefix, before, after) {
    return (
      `## Component ${name}:\n` +
      `${before.join("\n")}\n` +
      tripleCss(selector, propertyPrefix) +
      `${after.join("\n")}\n`
    );
  }
  const before = [
    "    Let draft be a signal \"\".",
    "    button:",
    "        on click:",
  ];
  const after = [
    "            Set draft to \"ready\".",
    "            Call recordDraft with draft.",
    "        span: \"Stage\"",
  ];
  await context.test("different CSS blocks do not stitch actions on opposite sides", () => {
    const source =
      `# Fixture\n\n${component("One", ".one", "a", before, after)}\n` +
      component("Two", ".two", "b", before, after);
    const created = fixture({ files: { "logos/fixture/src/main.lg": source } });
    try {
      assert(!rules(runFixture(created)).includes("duplicate-statement-block"));
    } finally {
      removeFixture(created.root);
    }
  });
  await context.test("six copied statements after closing CSS remain visible", () => {
    const source =
      `# Fixture\n\n${component("One", ".one", "a", [], behaviorBlock)}\n` +
      component("Two", ".two", "b", [], behaviorBlock);
    const created = fixture({ files: { "logos/fixture/src/main.lg": source } });
    try {
      assert(rules(runFixture(created)).includes("duplicate-statement-block"));
    } finally {
      removeFixture(created.root);
    }
  });
});

test("static triple-quoted View prose is one nonbehavior statement", () => {
  const prose = [
    "        p: \"\"\"",
    "            First sentence.",
    "            Second sentence.",
    "            Third sentence.",
    "            Fourth sentence.",
    "        \"\"\"",
  ].join("\n");
  const source =
    `# Fixture\n\n## Component One:\n    View:\n${prose}\n\n` +
    `## Component Two:\n    View:\n${prose}\n`;
  const created = fixture({ files: { "logos/fixture/src/main.lg": source } });
  try {
    assert(!rules(runFixture(created)).includes("duplicate-statement-block"));
  } finally {
    removeFixture(created.root);
  }
});

test("triple-quote text in comments cannot shield executable source", () => {
  const source =
    "# Fixture\n" +
    "# linter shield \"\"\"\n\n" +
    `## Component One:\n${behaviorBlock.join("\n")}\n\n` +
    "    # second commented delimiter \"\"\"\n\n" +
    `## Component Two:\n${behaviorBlock.join("\n")}\n`;
  const created = fixture({ files: { "logos/fixture/src/main.lg": source } });
  try {
    assert(rules(runFixture(created)).includes("duplicate-statement-block"));
    assert(!rules(runFixture(created)).includes("unterminated-triple-string"));
  } finally {
    removeFixture(created.root);
  }
});

test("triple literal interiors count as one logical definition line", () => {
  const prose = Array.from(
    { length: 12 },
    (_, index) => `            Sentence ${index}.`,
  ).join("\n");
  const source =
    "# Fixture\n\n## Component One:\n    View:\n        p: \"\"\"\n" +
    `${prose}\n` +
    "        \"\"\"\n";
  const created = fixture({
    files: { "logos/fixture/src/main.lg": source },
    policy: basePolicy({
      files: { maxPhysicalLines: 30, maxLogicalLinesPerDefinition: 5 },
    }),
  });
  try {
    assert(!rules(runFixture(created)).includes("max-logical-lines-per-definition"));
  } finally {
    removeFixture(created.root);
  }
});

test("an unterminated triple-quoted string fails explicitly", () => {
  const source =
    "# Fixture\n\n## Component One:\n    View:\n        css \"\"\"\n            .panel { color: red; }\n";
  const created = fixture({ files: { "logos/fixture/src/main.lg": source } });
  try {
    const failure = runFixture(created).failures.find(
      ({ rule }) => rule === "unterminated-triple-string",
    );
    assert.match(failure.message, /add the closing \"\"\"/);
  } finally {
    removeFixture(created.root);
  }
});

test("ordinary repeated static View shape is not mistaken for copied behavior", () => {
  const markup = [
    "    View:",
    "        section [class=\"panel\"]:",
    "            h2: \"Heading\"",
    "            p: \"Summary\"",
    "            div [class=\"detail\"]:",
    "                span: \"Label\"",
    "                strong: \"Value\"",
    "            footer: \"Boundary\"",
  ];
  const created = fixture({
    files: {
      "logos/fixture/src/main.lg":
        `# Fixture\n\n## Component One:\n${markup.join("\n")}\n\n` +
        `## Component Two:\n${markup.join("\n")}\n`,
    },
  });
  try {
    assert(!rules(runFixture(created)).includes("duplicate-statement-block"));
  } finally {
    removeFixture(created.root);
  }
});

test("unfinished markers fail without rejecting the LOGOS placeholder attribute", async (context) => {
  await context.test("a normal input placeholder passes", () => {
    const created = fixture({
      files: {
        "logos/fixture/src/main.lg":
          '# Fixture\n\n## Component Form:\n    View:\n        input [placeholder="Write a research question"]:\n        p: "A documented research hack is ordinary prose."\n',
      },
    });
    try {
      assert(!rules(runFixture(created)).some((rule) => rule.startsWith("forbidden-marker-")));
    } finally {
      removeFixture(created.root);
    }
  });
  await context.test("case-changed TODO and lorem ipsum fail at their exact lines", () => {
    const created = fixture({
      files: {
        "logos/fixture/src/main.lg":
          '# Fixture\n\n## Component Form:\n    View:\n        p: "todo"\n        span: "HACK"\n        strong: "Lorem ipsum"\n',
      },
    });
    try {
      const result = runFixture(created);
      assert(rules(result).includes("forbidden-marker-unfinished-work"));
      assert(rules(result).includes("forbidden-marker-unsafe-workaround"));
      assert(rules(result).includes("forbidden-marker-lorem-ipsum"));
    } finally {
      removeFixture(created.root);
    }
  });
});

test("module closure integration rejects an orphan LOGOS file", () => {
  const registration = {
    name: "fixture",
    directory: "logos/fixture",
    entry: "src/main.lg",
    logicalRoot: "src/app.lg",
    entryClosureLock: "pinned-transitive-scope-workaround",
    allowedDiagnostics: [],
    domBundle: false,
    testLeaves: [
      {
        path: "src/policy.lg",
        expectedTests: ["Policy is total"],
        minimumProperties: 1,
        minimumProven: 1,
      },
    ],
  };
  const moduleManifest = {
    schema: "macsad-logos-module-manifest/1",
    seed: 7,
    tiers: "all",
    proveFiniteProperties: true,
    projects: [registration],
  };
  const created = fixture({
    files: {
      "logos/fixture/Largo.toml":
        '[package]\nname = "fixture"\nversion = "0.1.0"\nauthors = []\nentry = "src/main.lg"\n\n[test]\nskip_budget = 0\n',
      "logos/fixture/src/main.lg":
        '# Fixture\n\nImport App from "./app.lg".\nImport Policy from "./policy.lg".\n\n## Main\nShow 1.\n',
      "logos/fixture/src/app.lg":
        '# App\n\nImport Policy from "./policy.lg".\n\n## To appValue () -> Int:\n    Return policyValue().\n',
      "logos/fixture/src/policy.lg":
        "# Policy\n\n## To policyValue () -> Int:\n    Return 1.\n\n## Test: Policy is total\n    For all booleans value:\n        Expect that value is equal to value.\n",
      "logos/fixture/src/orphan.lg":
        "# Orphan\n\n## To orphanValue () -> Int:\n    Return 0.\n",
    },
    moduleManifest,
  });
  try {
    const result = runFixture(created, { checkModuleGraph: true });
    const failure = result.failures.find(({ rule }) => rule === "module-closure");
    assert.match(failure.message, /orphan\/decorative/);
  } finally {
    removeFixture(created.root);
  }
});

test("a source-directory symlink is rejected before LOGOS files are traversed", () => {
  const created = fixture({
    files: {
      "linked-source/main.lg":
        "# Linked source\n\n## To linkedValue () -> Int:\n    Return 1.\n",
    },
  });
  try {
    mkdirSync(join(created.root, "logos", "fixture"), { recursive: true });
    symlinkSync(
      join(created.root, "linked-source"),
      join(created.root, "logos", "fixture", "src"),
      process.platform === "win32" ? "junction" : "dir",
    );
    const failure = runFixture(created).failures.find(({ rule }) => rule === "source-tree");
    assert.match(failure.locations[0], /logos\/fixture\/src:1$/);
    assert.match(failure.message, /source symlinks are forbidden/);
  } finally {
    removeFixture(created.root);
  }
});

test("debt cannot become a path allowlist or suppress a hard rule", () => {
  const created = fixture();
  try {
    const policy = basePolicy({
      debt: [
        {
          rule: "max-physical-lines",
          fingerprint: "0".repeat(64),
          locations: ["logos/fixture/src/main.lg:1"],
          reason: "An arbitrary path exception would let all future module growth avoid the source contract.",
          removalCondition: "This entry must be rejected because hard size limits are never debt eligible in policy.",
        },
      ],
    });
    write(created.policyPath, `${JSON.stringify(policy, null, 2)}\n`);
    assert.throws(
      () => loadSourcePolicy(created.policyPath),
      /only exact current scoped-CSS debt is eligible/,
    );
  } finally {
    removeFixture(created.root);
  }
});

test("unused debt fails closed instead of becoming a permanent exemption", () => {
  const policy = basePolicy({
    debt: [
      {
        rule: "scoped-css-preferred-length",
        fingerprint: "1".repeat(64),
        locations: ["logos/fixture/src/main.lg:5"],
        reason: "The reviewed line used to exceed the scoped CSS design length before a component extraction.",
        removalCondition: "Remove this entry once that exact source line no longer emits the matching lint finding.",
      },
    ],
  });
  const created = fixture({ policy });
  try {
    assert(rules(runFixture(created)).includes("stale-source-debt"));
  } finally {
    removeFixture(created.root);
  }
});
