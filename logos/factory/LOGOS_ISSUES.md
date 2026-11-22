# LOGOS issues found while building the factory

Each entry is a minimal reproduction against the toolchains the factory was built
with: `<logicaffeine checkout>/target/release/largo` (`largo 0.11.0`, dated
2026-11-20; issues 1–6) and `/mnt/build/macsad-target/release/largo` (`largo
0.11.0` built from the tree with `process.lg`, the file natives and
`httpclient.lg`, sha256 `b784aa26…`; issues 7–15). Where the factory works around
an issue, the entry says how, so the workaround can be removed when it is fixed.

---

## 1. A record with a `Seq` field gets a derived encoder but no derived decoder

`toJson_<Record>` is derived for a record holding `Seq of Text`, but
`fromJson_<Record>` is not. The interpreter reports the missing decoder only when
the call is reached, at run time; `largo check` reports it as an unknown function.
The compiler source says so on purpose (`lgx_lower/json.rs`, `decode_plan`: "A Seq,
a Result or a tuple field is not decoded, so the record gets no decoder"), so this
is a capability gap rather than a bug, but it means a record cannot both carry a
list and be a typed `Get … as <Record>` answer.

`src/main.lg`:

```logos
## A Tagged has:
    a name, which is Text.
    a tags, which is Seq of Text.

## Main

Let t be a new Tagged with name "a" and tags ["x", "y"].
Let j be toJson_Tagged(t).
Show j.
Inspect fromJson_Tagged(j):
    When Ok (back):
        Show back's tags.
    When Err (e):
        Show e.
```

```text
$ largo run --interpret
{"name":"a","tags":["x","y"]}
Unknown function: fromJson_Tagged
exit 1
$ largo check
error: Unknown function: fromJson_Tagged
  --> src/main.lg:12:9
exit 1
```

**Factory workaround.** `Verdict`, `Attempt`, `TrailEntry` and `Lemma` carry lists.
They keep the derived encoder and are decoded by hand in `src/records_decode.lg`
(`decodeVerdict`, `decodeAttempt`, `decodeTrailEntry`, `decodeLemma`), each a closed
shape check (`src/wire_shape.lg`) followed by total field reads. `factory
selftest` pins `decode(toJson(x)) == x` for every one, so the hand decoders can be
swapped for derived ones the day the derive learns `Seq` fields.

---

## 2. A kernel-vernacular `Definition` silently shadows an existing name, prelude names included

`largo check --kernel` / `largo prove --kernel` accept a `Definition` of a name that
already exists — a prelude constant (`False`, `Eq`, `Nat_add`) or a definition
earlier in the same document — and every LATER reference to the name means the
new definition. A theorem whose statement text reads `False` is then "proved"
with no axioms. (An `Axiom` of an existing name is refused: "checked assumption
cannot replace existing declaration".) Definitions made before the shadowing keep
their meaning, so the kernel stays consistent; what breaks is any reading of a
theorem's statement TEXT, which is exactly what an acceptance policy reads.

`shadow.lg`:

```text
Definition False : Prop := True.

Theorem false_holds : False := by exact I.

Print Axioms false_holds.
```

```text
$ largo check --kernel shadow.lg --json
{"blocks":[{"block":1,"output":""},{"block":2,"output":""},{"block":3,"output":"'false_holds' depends on no axioms"}],"checked":true,"error":null,"failed_block":null,"file":"shadow.lg","surface":"kernel_document"}
exit 0
```

The same with the statement a proof must establish:

```text
Definition main_statement : Prop := forall (n : Nat), Eq Nat (Nat_add n (Succ Zero)) n.

Definition main_statement : Prop := True.

Theorem main : main_statement := by exact I.
```

checks, with `'main' depends on no axioms`. And `Definition Eq : forall (A : Type), A -> A -> Prop := fun (A : Type) => fun (x : A) => fun (y : A) => True.` followed by
`Theorem bogus : Eq Nat Zero (Succ Zero) := by exact I.` checks too.

**Factory defence.** A submission may not declare any name that already exists in
the prelude or in the statement document. `src/vernacular_names.lg` and
`src/submission_policy.lg` list every name a
submission declares (definitions, theorems, axioms, inductives and their
constructors) and refuses the surface-changing commands outright (`Notation`,
`Macro`, `Open`, `Namespace`, `Section`, `Export`, …); the verifier then asks the
kernel itself whether each declared name is already bound (a probe document of
the statement plus `Check <name>.`), and refuses the submission if any is. The
proof must also be a theorem whose type is the statement's goal NAME, and the goal
is defined in the frozen statement preamble, so no later text can change it.

---

## 3. `Check` prints a function-typed domain without its parentheses

The kernel printer drops the parentheses around an arrow in domain position, so a
printed type reads as a different type. This reaches error messages too, which is
what the factory feeds back to a model as repair diagnostics.

`arrow.lg`:

```text
Definition apply_zero : (Nat -> Nat) -> Nat := fun (f : Nat -> Nat) => f Zero.

Check apply_zero.

Check dne.
```

```text
$ largo check --kernel arrow.lg --json
… "apply_zero : Nat -> Nat -> Nat" … "dne : Π(P:Prop). P -> False -> False -> P" …
```

`apply_zero` has type `(Nat -> Nat) -> Nat`, and `dne` has type
`Π(P:Prop). ((P -> False) -> False) -> P`; both print as right-nested arrows,
which parse as `Nat -> (Nat -> Nat)` and `P -> (False -> (False -> P))`.

**Factory note.** The kernel reference given to models (`src/ref_prose.lg`) states
the signatures it lists with their parentheses written by hand, and warns that
printed types right-associate.

---

## 4. `Expect output:` compares a tokenized rendering of the expected lines, not the lines

The indented lines under `Expect output:` are lexed as LOGOS tokens and re-joined
with spaces: punctuation gets spaces around it, a word starting with `#` is
dropped as a comment, and blank lines vanish. Any expected output with a colon,
a `#`, a `·` or a blank line cannot match.

`src/main.lg`:

```logos
## Main

Show "x".

## Test: a colon survives

Show "a: b".
Expect output:
    a: b

## Test: a hash survives

Show "#2 done".
Expect output:
    #2 done

## Test: a blank line survives

Show "a\n\nb".
Expect output:
    a

    b
```

```text
$ largo test
FAIL  a blank line survives
      Expected output "a b" — but the test printed "a\n\nb".
FAIL  a colon survives
      Expected output "a : b" — but the test printed "a: b".
FAIL  a hash survives
      Expected output "" — but the test printed "#2 done".
0 passed · 3 failed · 0 skipped · seed 0
```

**Factory workaround.** Tests compare against a `"""…"""` literal with
`Expect that … is equal to …` instead.

---

## 5. `largo prove --kernel` cannot emit a certificate

The plan's trusted verifier re-runs `largo prove --kernel --json --certificate`;
the CLI refuses the combination.

```text
$ largo prove --kernel t2.lg --json --certificate
error: the argument '--kernel' cannot be used with '--certificate'
exit 2
```

**Factory note.** `src/verdict.lg` classifies the `--json` report alone; the
certificate and the two-kernel `recheck` agreement are a verifier step that needs
this capability first.

---

## 6. A kernel `--json` report that fails drops the outputs of the blocks that checked

When a document fails at block `k`, the report's `blocks` is `[]`, not the outputs
of blocks `1 … k-1`, so a `Print Axioms` that ran before the failure is lost.

```text
Theorem ok : Eq Nat Zero Zero := by rfl.

Print Axioms ok.

Theorem bad : Eq Nat Zero (Succ Zero) := by rfl.
```

```text
$ largo check --kernel partial.lg --json
{"blocks":[],"checked":false,"error":"Tactic error: step 1 (`rfl`): `rfl` does not apply: Zero and Succ Zero do not convert\nin the goal\n⊢ Eq Nat Zero (Succ Zero)","failed_block":3,"file":"partial.lg","surface":"kernel_document"}
```

**Factory note.** The verdict parser treats a failed report as carrying no block
outputs; the axiom report is only read from a document that checked whole.

---

## 7. A multi-line `"""…"""` literal inside an indented block is misread

Three related failures, each with its own repro. At the top level of `## Main` or
of a `## Test`, the same literals work.

**(a) After `Let` or `Push`, or as a call argument, a multi-line literal does not
parse**, and the error points at the function header rather than the literal:

```logos
## To g () -> Text:
    Let x be """line one

line two""".
    Return x.

## Main

Show g().
```

```text
$ largo check
error: I expected a statement here — a sentence that does something, like 'Let', 'Set', 'Show', or 'Return'. …
   3 | ## To g () -> Text:
     |                    ^
  --> src/main.lg:3:20
```

The same body written as `Return """line one\n\nline two""".` checks and runs.

**(b) A literal whose content starts on the next line passes `largo check`, and the
binding then does not exist at run time:**

```logos
## To g () -> Text:
    Let x be """
        line one
        """.
    Return x.

## Main

Show g().
```

```text
$ largo check
Check passed
$ largo run --interpret
Undefined variable: x
exit 1
```

**(c) Once the program reaches `crypto.lg`, even `Return """…"""` fails:**

```logos
## To text () -> Text:
    Return """line one
line two""".

## To digest (t: Text) -> Seq of Int:
    Return sha256(text_bytes(t)).

## Main

Show text().
Show length of digest("abc").
```

```text
$ largo run --interpret
error: I expected a statement here — a sentence that does something, like 'Let', 'Set', 'Show', or 'Return'. …
   5 | line two""".
     |            ^
  --> src/main.lg:5:12
exit 1
```

Without the `digest` function (so without `crypto.lg` spliced in) the program prints
both lines. With `bytesToHex` (`bytes.lg`) instead of `sha256` it also works.

**Factory workaround.** The factory writes no multi-line literal at all: a text of
several lines is built from its lines (`joinLines` in `src/conventions.lg`, or
`join(lines, "\n")`).

---

## 8. In a multi-module program, a diagnostic can name the wrong line

In a program assembled from several files, an error is reported at a line of the
right file that has nothing to do with it. Before `httpclient.lg` existed, the
factory's `largo check` reported the unknown `HttpReply` — used only at
`src/host.lg:164`, in the header of `httpCall` — as:

```text
error: `HttpReply` is not a type this program declares or imports
  99 | The program's arguments, the program's own name first.
  --> src/host.lg:99:1
```

Line 99 is a `## Note` sentence 65 lines earlier. In a single-file program the same
error names the right line. Issue 7's parse errors were reported at
`src/reference.lg:30` and `:51` (a `## Note` sentence and a blank line) while the
literal at fault was further down the file. A minimal repro has not been isolated;
the factory's tree at the time reproduced it.

---

## 9. `"""…"""` literals dedent and strip their surrounding blank lines (undocumented)

`docs/imperative-mode.md` and `LOGOS_QUICKGUIDE.md` list `"""…"""` as a multiline
literal without saying that it removes one leading newline, ALL trailing newlines,
and the common indentation of its lines:

```logos
## Main

Let a be """abc
""".
Show length of a.
Let c be """abc

""".
Show length of c.
Let d be """  indented
  two""".
Show d.
```

```text
3
3
indented
two
```

A literal meant to end with a newline must add it: `"""…""" + "\n"`.

---

## 10. A lone `"` in a `## Note` (or a quote inside backticks there) silently swallows the rest of the file

A `## Note` whose prose holds an odd number of `"` characters — or a quoted text
inside a backtick code span, `` `""` `` or `` `"x"` `` — makes everything after it
disappear: the program after the note is not compiled, `largo check` passes, and
`largo run` prints nothing and exits 0. When a later note supplies the closing
quote, the definitions between the two notes vanish instead, and the symptom is a
bogus `Unknown function` / `is not a type this program declares` at a line that is
fine. Plain `""` or `"x"` without backticks is harmless. (Found with `largo
0.11.0`, sha256 `b784aa26…`, `/mnt/build/macsad-target/release/largo`.)

`src/main.lg`:

```text
# Repro

## Note
Answers `""` when empty.

## To f () -> Text:
    Return "x".

## Main

Show f().
```

```text
$ largo check
Check passed
$ largo run --interpret; echo "exit $?"
exit 0
```

With the note written `Answers the empty text when empty.` the run prints `x`.
`Answers a quote " alone.` fails the same way.

**Factory consequence.** A factory snapshot whose notes say `` `""` `` (for
example `wire.lg`'s accessors) ran `largo run --interpret -- reference` and every
`ingest` role silently, printing nothing and exiting 0. Issues 7 and 8 may share
this cause. **Coordinator workaround.** No prose in the coordinator's files holds a
`"` character; empty text is written as *the empty text*.

---

## 11. A record with an `Option` field cannot be used by a page: the WebAssembly build refuses it

A page that decodes (or only holds) a record with an `Option of Text` field passes
its tests on the tree-walker and the lowered VM, and `largo check` / `largo build`
then refuse the page for the browser:

```text
# App

## A Tagged has:
    a name, which is Text.
    a note, which is Option of Text.

## Page /

State:
    Let items be a new Seq of Tagged.

Actions:
    When the page loads:
        Get "/api/items" as Seq of Tagged, then loaded.

    To loaded (answer: Result of Seq of Tagged and HttpError):
        Inspect answer:
            When Ok (list):
                Set items to list.
            When Err (e):
                Set items to a new Seq of Tagged.

View:
    <ul>{for each t in items:}<li class="item">{t's name}</li>{end}</ul>
```

```text
$ largo test
PASS  pages/app.lg › items arrive
$ largo check
error: wasm AOT backend: unsupported display of a record field of a type with no display
   1 | # App
  --> pages/app.lg:1:1
```

Removing the `note` field makes the page build. `docs/frontend.md` describes typed
fetches of records without excluding `Option` fields.

**Coordinator workaround.** The website's answer records (`src/web_*.lg`) carry no
`Option` field; an absent value travels as the empty text, and each record's note
says which fields may be empty. The worker API, which no page decodes, keeps
`Option` fields where absence is meaningful.

---

## 12. A page's test run refuses the closure's unit tests that call a function

When a page imports a module that has its own `## Test` blocks, `largo test` also
runs those tests as page tests (`pages/app.lg › <name>`) on the lowered VM, and
refuses every one whose `Expect`, `Let` or `For all` calls a function:

```text
FAIL  pages/app.lg › percent is bounded
      tier: refused on lowered VM (an `Expect` that calls a function is carried out
      by the tree-walker running the test; a driven tier can carry only driving
      statements and statements that read the page)
```

The same tests pass when the module is the entry. A unit test of a function is
exactly what an import-free leaf holds, so a page cannot import a tested leaf.
MaCSad's page-suite runner (`scripts/logos-pages.mjs`) expects the opposite: it
counts every test in a page's import closure as one of the page's tests.

**Coordinator workaround.** The modules pages import (`src/web_*.lg`, `src/ui_*.lg`)
carry no tests of their own; they are exercised through the pages' driven tests,
and the coordinator's tested policy lives in leaves no page imports.

---

## 13. Some everyday words cannot be names, and the error says something else

`chunk` is a reserved word in imperative mode (`TokenType::Chunk`, lexer.rs:3557)
although the imperative guide says everyday words work as names in every
position. The parse error names a missing word instead:

```logos
## To grow (chunk: Int) -> Int:
    Return chunk + 1.

## Main

Show grow(2).
```

```text
$ largo check
error: This construction needs the word 'at' here to complete its shape. …
   2 |     Return chunk + 1.
     |                  ^
```

In a multi-module program the same error was reported at an unrelated line
(issue 8). Separately, a record field named `order` (`an order, which is Seq of
Text.`) passes `largo test` but `largo check` reports `'AtlasGraph' has no field
named 'order'`.

**Factory workaround.** The names are `pieceSize` and `ids`.

---

## 14. The visibility check of `largo run` attributes imported modules' code to the entry

A program whose entry imports a module that itself imports another fails
`largo run --interpret` with an error that blames the ENTRY for a name only the
imported module uses — while `largo test` and `largo check` pass. With the
factory's own modules (`main.lg` importing only `Shared`, which imports `Wire`):

```text
$ largo run --interpret
error: `textAt` is used in `main.lg` but not imported there — it is defined in `wire.lg`. …
```

A three-file minimal repro (`base.lg` ← `mid.lg` ← `main.lg`) did not reproduce
it, so the trigger is size- or content-dependent.

**Factory workaround.** The entry imports every module once — the
`pinned-transitive-scope-workaround` the macsad projects already declare in
`tests/logos-module-manifest.json`.

**Still present in largo 0.11.0** (`/mnt/build/macsad-target/release/largo`,
sha256 `bdaa1cb2…`, 2026-11-22): with the full factory (core, coordinator,
worker and verifier) and a `main.lg` importing only `roles.lg`, `largo check`
fails with ``error: `tooLarge` is used in `main.lg` but not imported there — it
is defined in `http_answers.lg` `` and the same for `clampOffset`
(`api_bounds.lg`), `isRecordStart` (`opdp_import_rules.lg`) and
`openShapeProblem` (`wire_shape.lg`). The entry therefore still imports every
module, which caps the project at 115 modules under the 120-line file limit
(`main.lg` is the title, the imports and a one-line `## Main`).

---

## 15. One async native anywhere moves the whole program off the VM

A program whose closure contains `runProcess`, `httpRequest` (or other natives
the bytecode VM does not take) runs entirely on the tree-walker under `largo run
--interpret`, and `largo test --tiers all` refuses every one of its tests on the
VM — including tests of pure functions that never reach a native:

```text
$ largo test --tiers all            # in logos/factory, at the project level
FAIL  MSC subjects map onto the atlas's categories [code=3, category="logic"]
      tier: refused (the computation needs the async runtime (file I/O, sleep, serve, or networking) — the bytecode VM is sync-only)
… 115 test(s) failed
```

The same tests pass on both tiers when each test leaf is run alone (as macsad's
`verify-logos-tests.mjs` runs them). The cost is large for byte loops: the OPDP
scanner takes 3.7 s for 11 MB in a program of its own (VM and JIT) and about 41 s
for 18 MB inside the factory (tree-walker).

**Factory note.** The production path is the compiled binary (`largo build
--release`), where the tier question does not arise.

---

## 16. The factory does not compile to Rust: `largo build --release` fails in the generated code

The interpreter runs the whole factory (`largo test`: 115 passed; `factory
selftest --live`: all ten groups pass), but the AOT build fails inside the
generated Rust with 126 errors, and largo says so itself.

```text
$ cd logos/factory && LOGOS_WORKSPACE=<logicaffeine checkout> largo build --release
…
error: could not compile `factory` (bin "factory-a112f426913dc2e7") due to 126 previous errors; 195 warnings emitted
error: the generated Rust failed to compile — this is a LOGOS compiler bug, not an error in your program
```

The 126 errors fall into five shapes:

- 96 × E0308, mismatched types. One is `std`'s own `jsonGet` (`return en.val;`, expected
  `Json`, found `LogosInt`): `JEntry`'s `val` is typed as an integer in this
  program. Another is integer fields built as `LogosInt::from(0)` where `i64` is expected.
- 17 × E0277, `LogosInt: From<Json>`. Every `a new JEntry with key … and val (a new JStr with s …)` is built through
  `LogosInt::from(Json::JStr { … })`.
- 2 × E0369, `LogosSeq<RefExample> + LogosSeq<RefExample>`. `+` on two `Seq`s of a
  record, which the interpreter runs, has no `Add` in the runtime.
- 5 × E0599. `format!(…).borrow()`: a hole-interpolated text passed by reference.
- E0382, a moved value used again: `p` partially moved, `number` moved.

A minimal repro has not been isolated: each try is a full release build of the
runtime crates. The generated project is kept at `target/release/build` by largo.

**Factory note.** Until this is fixed, the factory runs as `largo run --interpret
-- <role>`, which, with issue 15, means the tree-walker.

---

## 17. A field named like a standard-library function splices that module in, and its own warnings land on the user's file

A record field (or any word) that happens to be the name of a function in a large
standard-library module makes the prelude include the module, and the module's own
code then raises `orphaned-copy` warnings (`'y' is a copy of 'b'`, from
`lapack.lg`'s `Let mutable y be b.`) reported against line 1 of the user's entry
file. MaCSad's verification gate accepts only exact unused-import warnings, so the
stray warnings fail it.

```logos
# Repro

## A Row has:
    a name, which is Text.
    a rank, which is Int.

## Main

Let r be a new Row with name "a" and rank 2.
Show r's rank.
```

```text
$ largo check
warning: 'y' is a copy of 'b' — collections and records are values in LOGOS, so this mutates
the copy, never 'b' itself. Either write it back (`Set b to y.`), or mutate 'b' directly.
   1 | # Repro
  --> src/main.lg:1:1
(twice)
Check passed
```

Renaming the field to `place` removes both warnings: `rank` is a function of
`lapack.lg`. **Coordinator workaround.** The website's records name the field
`rankBp` (the rank in basis points, which is also the more precise name).

## 18. A function passed by name as a value checks, then is an undefined variable at run time

```logos
## To canonPairs (text: Text) -> Result of Text and Text:
    Return a new Ok with value text.

## To listWith (r: Result of Text and Text, canon: fn(Text) -> Result of Text and Text) -> Text:
    Inspect r:
        When Ok (text):
            Inspect canon(text):
                When Ok (t):
                    Return t.
                When Err (e):
                    Return e.
        When Err (e):
            Return e.
    Return "none".

## Main

Show listWith(a new Ok with value "x", canonPairs).
```

```text
$ largo check
Check passed
$ largo run --interpret
Undefined variable: canonPairs
```

**Coordinator workaround.** No function value is passed; each list route calls its
own typed reader and shares only the answer helper (`routes_problem.lg`'s `listAnswer`).

---

## 19. `routeQuery()` with no argument passes `largo check` and stops the page mounting; a test's `Navigate` query is not seen

`routeQuery` takes the parameter's name (`routeQuery("id")`), although
`docs/frontend.md` says `routePath` and `routeQuery` "answer the current path and
query". Called with no argument it passes `largo check`, and the page then never
mounts in a test (every selector is "No element matches"). With the name, it
answers the empty text after a test's `Navigate to "/problem?id=opdp%3A7"`, while
`the URL` is `/problem?id=opdp%3A7`.

```logos
## Page /problem

State:
    Let shown be "none".

Actions:
    When the page loads:
        Set shown to routeQuery("id").

    When the route changes:
        Set shown to routeQuery("id").

View:
    <p id="shown">[{shown}]</p>

## Test: the route opens the problem it names

Navigate to "/problem?id=opdp%3A7".
Expect that the URL is equal to "/problem?id=opdp%3A7".
Expect that the text of "#shown" is equal to "[opdp:7]".
```

```text
FAIL  pages/app.lg › the route opens the problem it names
      Expected that … is "[opdp:7]".        (it is "[]")
```

**Coordinator workaround.** The problem page reads `routeQuery("id")` when it
loads (a real browser has the query) and also offers a form that opens a problem
by id, which is what its tests drive.

## 20. `Given that … answers … with <name>` takes no variable, only a literal

A JSON body held in a `Let` and named in `Given that GET "…" answers 200 with body.`
answers nothing the page can decode; the same text written as the literal works.
Long bodies are therefore written as multi-line `"""…"""` literals in place, which
the source-line limit also asks for.

---

## 21. On the tree-walker, the same standard-library call is twenty times slower inside a large program

Measured with `largo run --interpret` on one 10 KB OPDP record and one 8 MB piece
of the release, both programs containing `runProcess` (so both on the tree-walker):

| call | small program (3 modules) | the factory (≈120 modules) |
|---|---|---|
| `jsonParseStrict` of a 10 KB record | 3 ms | 94 ms |
| `lines` of an 8 MB text | 1.0 s | 14.0 s |

No user function shadows a standard-library name (checked by listing both). The
cost per call grows with the program, not with the data.

**Consequence.** `factory coordinator import-opdp` reads the 102,819 records at
about seven a second (about four hours) inside the factory, where the same loop in
a small program would take minutes; with `largo build --release` failing
(§16) there is no compiled alternative yet.
