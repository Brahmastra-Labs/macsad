#!/usr/bin/env node

import { spawnSync } from "node:child_process";

const repository = "Brahmastra-Labs/macsad";
const organization = "Brahmastra-Labs";
const runnerGroupName = "macsad-firebat2";
const admittedWorkflow =
  "Brahmastra-Labs/macsad/.github/workflows/firebat2-verify.yml@refs/heads/main";

function stop(message) {
  process.stderr.write(`error: ${message}\n`);
  process.exit(1);
}

function get(path) {
  const result = spawnSync("gh", ["api", "--method", "GET", path], {
    encoding: "utf8",
    maxBuffer: 1024 * 1024,
    stdio: ["ignore", "pipe", "pipe"],
  });
  if (result.error) stop(`gh could not start: ${result.error.message}`);
  if (result.status !== 0) {
    if (result.stderr) process.stderr.write(result.stderr);
    stop(`read-only GitHub audit failed for ${path}`);
  }
  try {
    return JSON.parse(result.stdout);
  } catch (error) {
    stop(`GitHub returned invalid JSON for ${path}: ${error.message}`);
  }
}

const permissions = get(`repos/${repository}/actions/permissions`);
if (
  permissions.enabled !== true ||
  permissions.allowed_actions !== "selected" ||
  permissions.sha_pinning_required !== true
) {
  stop("repository Actions permissions are not enabled + selected + full-SHA required");
}

const selected = get(`repos/${repository}/actions/permissions/selected-actions`);
if (
  selected.github_owned_allowed !== true ||
  selected.verified_allowed !== false ||
  !Array.isArray(selected.patterns_allowed) ||
  selected.patterns_allowed.length !== 0
) {
  stop("selected-actions policy drifted from GitHub-owned-only with no patterns");
}

const workflowPermissions = get(`repos/${repository}/actions/permissions/workflow`);
if (
  workflowPermissions.default_workflow_permissions !== "read" ||
  workflowPermissions.can_approve_pull_request_reviews !== false
) {
  stop("default workflow token must remain read-only and unable to approve pull requests");
}

const variable = get(`repos/${repository}/actions/variables/FIREBAT2_ENABLED`);
if (
  variable.name !== "FIREBAT2_ENABLED" ||
  !["false", "true"].includes(variable.value)
) {
  stop("FIREBAT2_ENABLED must be a canonical boolean repository variable");
}

if (variable.value === "false") {
  process.stdout.write(
    "GitHub Actions audit passed: GitHub-owned/full-SHA actions, read-only token, no PR approval; Firebat2 remains disabled.\n",
  );
} else {
  const runnerGroups = get(`orgs/${organization}/actions/runner-groups`);
  if (!Array.isArray(runnerGroups.runner_groups)) {
    stop("organization runner-group response omitted runner_groups");
  }
  const matchingGroups = runnerGroups.runner_groups.filter(
    (group) => group.name === runnerGroupName,
  );
  if (matchingGroups.length !== 1) {
    stop("the organization must contain exactly one macsad-firebat2 runner group");
  }
  const group = matchingGroups[0];
  if (
    group.default === true ||
    group.inherited !== false ||
    group.visibility !== "selected" ||
    group.allows_public_repositories !== false ||
    group.restricted_to_workflows !== true ||
    !Array.isArray(group.selected_workflows) ||
    group.selected_workflows.length !== 1 ||
    group.selected_workflows[0] !== admittedWorkflow
  ) {
    stop("macsad-firebat2 must be private, selected-repository, and restricted to the exact verifier workflow");
  }

  const selectedRepositories = get(
    `orgs/${organization}/actions/runner-groups/${group.id}/repositories`,
  );
  if (
    selectedRepositories.total_count !== 1 ||
    !Array.isArray(selectedRepositories.repositories) ||
    selectedRepositories.repositories.length !== 1 ||
    selectedRepositories.repositories[0].full_name !== repository ||
    selectedRepositories.repositories[0].private !== true
  ) {
    stop("macsad-firebat2 must be assigned only to the private Brahmastra-Labs/macsad repository");
  }

  process.stdout.write(
    "GitHub Actions audit passed: Firebat2 enabled with an exact private repository/workflow runner-group boundary.\n",
  );
}
