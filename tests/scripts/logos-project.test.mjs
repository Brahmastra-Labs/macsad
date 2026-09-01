import assert from "node:assert/strict";
import {
  mkdirSync,
  mkdtempSync,
  realpathSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, sep } from "node:path";
import test from "node:test";
import {
  inspectProject,
  inspectRegisteredProjects,
  LogosProjectError,
} from "../../scripts/logos-project.mjs";

const temporaryBase = realpathSync(tmpdir());

function write(path, contents) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, contents, { encoding: "utf8", flag: "wx" });
}

function registration(overrides = {}) {
  return {
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
    ...overrides,
  };
}

function fixture(mutator = () => {}) {
  const root = mkdtempSync(join(temporaryBase, "macsad-module-guard-"));
  const project = join(root, "logos", "fixture");
  mkdirSync(join(project, "src"), { recursive: true });
  write(
    join(project, "Largo.toml"),
    '[package]\nname = "fixture"\nversion = "0.1.0"\nauthors = []\nentry = "src/main.lg"\n\n[test]\nskip_budget = 0\n',
  );
  write(
    join(project, "src", "main.lg"),
    '# Fixture\n\nImport App from "./app.lg".\nImport Policy from "./policy.lg".\n\n## Main\nShow 1.\n',
  );
  write(
    join(project, "src", "app.lg"),
    '# App\n\nImport Policy from "./policy.lg".\n\n## To appValue () -> Int:\n    Return policyValue().\n',
  );
  write(
    join(project, "src", "policy.lg"),
    '# Policy\n\n## To policyValue () -> Int:\n    Return 1.\n\n## Test: Policy is total\n    For all booleans value:\n        Expect that value is equal to value.\n',
  );
  mutator({ project, root });
  return { project, root };
}

function removeFixture(root) {
  const canonical = realpathSync(root);
  if (!canonical.startsWith(`${temporaryBase}${sep}macsad-module-guard-`)) {
    throw new Error(`refusing to remove unexpected fixture path: ${canonical}`);
  }
  rmSync(canonical, { recursive: true });
}

test("discovers the exact physical and logical import closure", () => {
  const { root } = fixture();
  try {
    const inspected = inspectProject(registration(), root);
    assert.deepEqual(inspected.closure, ["src/app.lg", "src/main.lg", "src/policy.lg"]);
    assert.deepEqual(inspected.postorder, ["src/policy.lg", "src/app.lg", "src/main.lg"]);
    assert.equal(inspected.suites.length, 1);
    assert.match(inspected.closureDigest, /^[0-9a-f]{64}$/);
  } finally {
    removeFixture(root);
  }
});

test("rejects a module present only through the compatibility entry lock", () => {
  const { root, project } = fixture(({ project: fixtureProject }) => {
    write(
      join(fixtureProject, "src", "decorative.lg"),
      "# Decorative\n\n## To decoration () -> Int:\n    Return 0.\n",
    );
    const entryPath = join(fixtureProject, "src", "main.lg");
    const entry = '# Fixture\n\nImport App from "./app.lg".\nImport Policy from "./policy.lg".\nImport Decorative from "./decorative.lg".\n\n## Main\nShow 1.\n';
    rmSync(entryPath);
    write(entryPath, entry);
  });
  try {
    assert.throws(
      () => inspectProject(registration(), root),
      (error) => error instanceof LogosProjectError && /not the logical graph/.test(error.message),
    );
  } finally {
    removeFixture(root);
  }
});

test("rejects a source file missing from the entry closure lock", () => {
  const { root, project } = fixture();
  try {
    write(
      join(project, "src", "orphan.lg"),
      "# Orphan\n\n## To orphanValue () -> Int:\n    Return 0.\n",
    );
    assert.throws(
      () => inspectProject(registration(), root),
      (error) => error instanceof LogosProjectError && /outside the entry import closure/.test(error.message),
    );
  } finally {
    removeFixture(root);
  }
});

test("rejects every repository LOGOS source outside registered closures", async (context) => {
  await context.test("source beside rather than inside registered src", () => {
    const { root, project } = fixture();
    try {
      write(
        join(project, "examples", "ignored.lg"),
        "# Ignored\n\n## To ignoredValue () -> Int:\n    Return 0.\n",
      );
      assert.throws(
        () => inspectRegisteredProjects({ projects: [registration()] }, root),
        (error) => error instanceof LogosProjectError && /every repository \.lg file/.test(error.message),
      );
    } finally {
      removeFixture(root);
    }
  });

  await context.test("unregistered project manifest", () => {
    const { root } = fixture();
    try {
      write(
        join(root, "logos", "hidden", "Largo.toml"),
        '[package]\nname = "hidden"\nversion = "0.1.0"\nentry = "src/main.lg"\n\n[test]\nskip_budget = 0\n\n[dependencies]\nforeign = "1"\n',
      );
      assert.throws(
        () => inspectRegisteredProjects({ projects: [registration()] }, root),
        (error) => error instanceof LogosProjectError && /every LOGOS Largo\.toml/.test(error.message),
      );
    } finally {
      removeFixture(root);
    }
  });
});

test("rejects bare imports and registry dependency sections", async (context) => {
  await context.test("bare import", () => {
    const { root, project } = fixture();
    try {
      const entryPath = join(project, "src", "main.lg");
      rmSync(entryPath);
      write(entryPath, "# Fixture\n\nImport App.\n\n## Main\nShow 1.\n");
      assert.throws(
        () => inspectProject(registration(), root),
        (error) => error instanceof LogosProjectError && /imports must use exactly/.test(error.message),
      );
    } finally {
      removeFixture(root);
    }
  });

  await context.test("late import outside the first abstract paragraph", () => {
    const { root, project } = fixture();
    try {
      const entryPath = join(project, "src", "main.lg");
      rmSync(entryPath);
      write(
        entryPath,
        '# Fixture\n\nThis paragraph is prose.\n\nImport App from "./app.lg".\nImport Policy from "./policy.lg".\n\n## Main\nShow 1.\n',
      );
      assert.throws(
        () => inspectProject(registration(), root),
        (error) =>
          error instanceof LogosProjectError && /outside the compiler-scanned/.test(error.message),
      );
    } finally {
      removeFixture(root);
    }
  });

  await context.test("noncanonical relative import", () => {
    const { root, project } = fixture();
    try {
      const entryPath = join(project, "src", "main.lg");
      rmSync(entryPath);
      write(
        entryPath,
        '# Fixture\n\nImport App from "./nested/../app.lg".\nImport Policy from "./policy.lg".\n\n## Main\nShow 1.\n',
      );
      assert.throws(
        () => inspectProject(registration(), root),
        (error) => error instanceof LogosProjectError && /import path is not canonical/.test(error.message),
      );
    } finally {
      removeFixture(root);
    }
  });

  await context.test("registry section", () => {
    const { root, project } = fixture();
    try {
      const manifestPath = join(project, "Largo.toml");
      rmSync(manifestPath);
      write(
        manifestPath,
        '[package]\nname = "fixture"\nversion = "0.1.0"\nentry = "src/main.lg"\n\n[test]\nskip_budget = 0\n\n[dependencies]\nforeign = "1"\n',
      );
      assert.throws(
        () => inspectProject(registration(), root),
        (error) => error instanceof LogosProjectError && /dependencies.*forbidden/.test(error.message),
      );
    } finally {
      removeFixture(root);
    }
  });
});

test("rejects tests in an importing module or an unregistered module", async (context) => {
  await context.test("test-bearing importer", () => {
    const { root, project } = fixture();
    try {
      const appPath = join(project, "src", "app.lg");
      rmSync(appPath);
      write(
        appPath,
        '# App\n\nImport Policy from "./policy.lg".\n\n## To appValue () -> Int:\n    Return policyValue().\n\n## Test: App is wired\n    Expect that appValue() is 1.\n',
      );
      assert.throws(
        () => inspectProject(registration(), root),
        (error) => error instanceof LogosProjectError && /would be invisible/.test(error.message),
      );
    } finally {
      removeFixture(root);
    }
  });

  await context.test("registered leaf grows an import", () => {
    const { root, project } = fixture();
    try {
      const policyPath = join(project, "src", "policy.lg");
      rmSync(policyPath);
      write(
        policyPath,
        '# Policy\n\nImport App from "./app.lg".\n\n## Test: Policy is total\n    For all booleans value:\n        Expect that value is equal to value.\n',
      );
      assert.throws(
        () => inspectProject(registration(), root),
        (error) => error instanceof LogosProjectError && /cycle is forbidden|import-free leaf/.test(error.message),
      );
    } finally {
      removeFixture(root);
    }
  });
});
