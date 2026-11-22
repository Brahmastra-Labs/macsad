# LOGOS issues found while building the factory

Each entry is a minimal reproduction against the toolchain the factory was built
with: `/home/tristen/logicaffeine/target/release/largo`, `largo 0.11.0` (binary
dated 2026-11-20). Where the factory works around an issue, the entry says how,
so the workaround can be removed when the issue is fixed.

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
They keep the derived encoder and are decoded by hand in `src/shared.lg`
(`decodeVerdict`, `decodeAttempt`, `decodeTrailEntry`, `decodeLemma`), each a closed
shape check (`src/wire.lg`) followed by total field reads. Round-trip tests pin
`decode(toJson(x)) == x` for every one, so the hand decoders can be swapped for
derived ones the day the derive learns `Seq` fields.

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
the prelude or in the statement document. `src/submission.lg` lists every name a
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

**Factory note.** The kernel reference given to models (`src/reference.lg`) states
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

**Factory workaround.** No function body holds a multi-line literal: a text of
several lines is written as `joinLines(["line one", "", "line two"])`
(`src/reference.lg`, `src/submission.lg`). Multi-line literals appear only at the
top level of `## Test` blocks.

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
