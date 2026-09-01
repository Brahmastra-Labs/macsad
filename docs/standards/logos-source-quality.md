# LOGOS source-quality bumpers

MaCSad treats source shape as an executable maintainability contract. Run the
credential-free check before requesting review:

```bash
node scripts/logos-source-lint.mjs
```

`scripts/dev.sh test-foundation` and the Foundation CI workflow run the same
command and its adversarial test suite. The sole policy file is
`.macsad/policies/logos-source-quality.json`, backed by the real repo-relative
`.macsad/schemas/logos-source-quality-v1.schema.json`; changing a threshold also
requires updating the test that pins the exact checked-in values. The linter
does not rewrite source and has no path-wide ignore mechanism.

## Exact limits

| Contract | Limit | Required response |
|---|---:|---|
| Physical lines in one `.lg` module | 120 | Split the module at a responsibility/import boundary. |
| Nonblank logical lines in one `##` definition | 80 | Extract policy to a `## To` definition or UI to a child `## Component`. |
| Ordinary physical line length | 220 characters | Extract prose, a helper, or a child component. |
| Single-line scoped-CSS preferred line length | 1,200 characters | Split the owning View or use a readable triple-quoted literal before changing the exact style string. |
| Single-line scoped-CSS hard line length | 4,600 characters | The change is rejected; debt cannot suppress this limit. |
| Each physical line inside a triple-quoted literal | 220 characters | Wrap the literal; multiline syntax is not a long-line escape hatch. |
| Repeated scoped-CSS block | 8 or more declarations, second occurrence | Reuse a style-capable component when scoping semantics permit it. |
| Repeated normalized statement block | 6 statements, including at least 2 behavior statements, second occurrence | Extract one policy helper or child component. |

The duplicate statement check operates within and across `.lg` files. It
normalizes insignificant whitespace but preserves names and literals. It
requires behavior-bearing statements such as `Let`, `Set`, `Call`, `Return`,
events, conditions, loops, or expectations, so ordinary repeated View
hierarchy and definition headers do not create noise. As the LOGOS lexer does,
the gate erases `#` comments only outside strings before counting logical lines,
classifying behavior, comparing statement tokens, or parsing CSS. Comments
therefore cannot disguise a copy, while a `#` inside an ordinary, raw, or
triple-quoted string remains semantic. Raw source remains authoritative for
physical length and unfinished-marker checks.

Plain `css "…"`, raw `css r"…"`, multiline `css """…"""`, and raw-prefixed
multiline literals are all inspected as complete CSS bodies because the pinned
LOGOS lexer produces a string token for each form. Declaration counting and
duplicate fingerprints cover the entire dedented body. CSS contributes exactly
one statement-block boundary, so its internal lines are not code and behavior
on opposite sides cannot be stitched into a false duplicate.

Any other triple-quoted string is likewise represented as one statement whose
identity includes the literal digest. Its interior prose cannot masquerade as
imperative lines merely because sentences end in periods. The closing delimiter
ends the masked range, so executable statements after it remain lint-visible;
an unterminated triple-quoted string fails explicitly.

The source gate also rejects orphan/decorative modules through the registered
module closure, source symlinks, and unfinished markers (`TODO`, `FIXME`,
`HACK`, `XXX`, `TBD`, `TBC`, `CHANGEME`, `PLACEHOLDER`, and `lorem ipsum`). A
normal lowercase LOGOS `placeholder=` input attribute is not an unfinished-work
marker.

## Baseline debt is a tripwire, not an exemption

Four pre-policy scoped-style findings are recorded in the policy. Each entry
names only an eligible scoped-CSS rule, the SHA-256 of the exact normalized CSS,
its exact source line or lines, a reason, and a removal condition. The linter
prints these findings on every run.

The debt mechanism fails closed:

- only preferred scoped-CSS length and duplicate scoped-CSS findings are
  eligible;
- file, definition, ordinary-line, hard-CSS, duplicate-behavior, marker, and
  module-closure rules cannot be suppressed;
- moving, editing, growing, or copying the fingerprinted CSS invalidates the
  entry; and
- an entry whose finding disappeared is stale and fails until removed.

Do not alter product source only to make a metric green. Split only at a real
domain, policy, state-ownership, or component boundary. If the correct split
depends on a missing LOGOS facility, preserve the exact visible debt and track
the framework gap rather than moving policy into JavaScript, global CSS, or a
host adapter.

## Failure workflow

1. Read the rule, locations, fingerprint, and suggested extraction seam.
2. Confirm the behavior with the smallest relevant source-linter fixture.
3. Refactor at a real boundary without changing behavior.
4. Run `node --test tests/scripts/logos-source-lint.test.mjs`.
5. Run `scripts/dev.sh test-foundation`, then the full LOGOS quality gate before
   handoff.

Never increase a limit, weaken behavior classification, add debt, or change a
fingerprint merely to admit a feature. Those are policy changes and must be
reviewed as such with an adversarial fixture proving the new boundary.
