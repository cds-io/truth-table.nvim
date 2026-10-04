# truth-table.nvim

[GitHub: cds-io/truth-table.nvim](https://github.com/cds-io/truth-table.nvim)

Generate Markdown truth tables, evaluate Boolean expressions, and work through
logic rewrites inside Neovim.

Start with variable names or an expression. The plugin generates every input
combination, adds computed columns, and formats the result as a centered table:

```markdown
|  A  |  B  | A ∧ B | A → B |
|:---:|:---:|:-----:|:-----:|
|  0  |  0  |   0   |   1   |
|  0  |  1  |   0   |   1   |
|  1  |  0  |   0   |   0   |
|  1  |  1  |   1   |   1   |
```

You can expand existing tables, preview algebraic rewrites, record derivation
steps, and generate Karnaugh maps with sum-of-products formulas. A built-in
tutorial introduces the workflow through short, editable exercises.

This is a personal plugin extracted from a long-maintained Neovim configuration
and developed with help from a coding agent.

## Installation

With lazy.nvim:

```lua
return {
    "cds-io/truth-table.nvim",
    lazy = false,
}
```

The plugin registers commands and default mappings automatically. which-key is
optional. Eager loading makes the global insert-mode abbreviations available at
startup; command-based lazy loading registers them when the plugin first loads.

The logic modules use Lua 5.1. Editor integration uses Neovim APIs.

## Quick start

Create a table above the current line:

```vim
:TruthTable A B
```

Put the cursor in the table and append computed columns:

```vim
:TruthTableExpand A and B, A implies B
```

Or generate the inputs and computed columns together:

```vim
:TruthTable A and B | A implies B
```

To replace an expression line with its table, run `:.TruthTable`. A range reads
all selected lines, treating each line break as another expression separator.

For an algebraic rewrite, put this expression on its own line:

```text
S ∨ (A ∧ ¬C) ∨ (G ∧ ¬C)
```

Place the cursor on `¬C` and run `:TruthTableFactor`. The preview shows:

```text
S ∨ (¬C ∧ (A ∨ G))
```

Use `:TruthTableApply` to replace the expression, or `:TruthTableApplyStep` to
keep it and insert the equivalent expression as the next derivation step.

Run `:TruthTableTutor` for guided exercises, or `:help truth-table.txt` for the
help file.

A table with N variables has 2^N data rows, so generation grows exponentially.
Start with small expressions.

## Commands

| Command | Effect |
|---|---|
| `:TruthTable {N\|names}` | Insert a new table above the current line: `N` variables (A, B, ...) or named ones |
| `:TruthTable {exprs}` | Insert a new table from expressions separated by `\|` or `,`: the variables they mention, plus a computed column per expression |
| `:[range]TruthTable` | Same, reading the argument from the selected lines (a line break is one more `\|`) and replacing them with the table |
| `:TruthTableExpand {preds}` | Append a computed column per comma-separated predicate |
| `:TruthTableDeMorgan` | Toggle a De Morgan preview at the nearest match around the cursor, in an expression or the current column header |
| `:TruthTableFactor` | Toggle a preview that factors the operand under the cursor out of the terms sharing it |
| `:TruthTableDistribute` | Toggle a preview that distributes the operand under the cursor into the group beside it |
| `:TruthTableXor` | Toggle a preview that recognises an exclusive or (or an equivalence) spelled out as the two terms under the cursor |
| `:TruthTableCommute[!]` | Toggle a preview that swaps the operand under the cursor with the next one (`!`: the previous one) |
| `:TruthTableApply` | Apply the pending preview in place (`:TruthTableDeMorganApply` is an alias) |
| `:TruthTableApplyStep` | Insert the pending preview below the line as a `≡` derivation step |
| `:TruthTableToggle` | Toggle data cells between `0/1` and `F/T` |
| `:TruthTableDropRow` | Drop the row under the cursor |
| `:TruthTableDropColumn` | Drop the column under the cursor |
| `:TruthTableKarnaugh` | Insert, below the table, a Karnaugh map and a simplified sum-of-products formula for the column under the cursor |
| `:TruthTableTutor[!] [lesson]` | Open the tutorial at your place: a lesson pane beside a scratch pane, in a new tab (`!` starts over, a number jumps to that lesson) |
| `:TruthTableTutorNext` | Go to the tutorial's next step (`]]` inside the tutor) |
| `:TruthTableTutorPrev` | Go to the tutorial's previous step (`[[` inside the tutor) |

```
:TruthTable 3
:TruthTable p q r
:TruthTable (m ∧ (a ⊕ b) ∨ (¬m ∧ (a ∧ b))) | m ⊕ (a ∧ b)
:TruthTableExpand A and B, A xor B
```

The expression form reads its variables off the expressions, in order of first
appearance (m, a, b above). A bare variable adds no column, so it can pin the
order: `:TruthTable b | a | a -> b` puts `b` first. (The operator keywords are
reserved: `:TruthTable p or q` is the expression `p ∨ q`.)

## Predicate language

Used by `:TruthTableExpand` and the expression form of `:TruthTable`. Operands
are column names and the literals `0` / `1`. Operators, tightest binding first:

| Operator | Meaning | Rendered |
|---|---|---|
| `not` / `!` / `¬` | negation | `¬` |
| `and` / `∧` | conjunction | `∧` |
| `or` / `∨` | disjunction | `∨` |
| `xor` / `⊕` | exclusive or | `⊕` |
| `implies` / `->` / `=>` / `→` / `⇒` | implication | `→` |
| `iff` / `=` / `<->` / `<=>` / `⇔` / `↔` | equivalence | `⇔` |

Binary operators associate to the left, including implication. Use parentheses
for `A -> (B -> C)`. Parentheses override precedence: `(A or B) and !C`.
Each operator can be typed as its symbol, so formula headings can be used as
expressions. Headings generated from positional references describe stored column values.
Use positional references again to read those values; see
[Editing existing tables](#editing-existing-tables). Markdown source escapes literal backticks, pipes,
and backslashes; use the decoded label when referencing a column.
New-table expressions must mention at least one variable; constant-only
expressions are supported by expansion of an existing table.

Parse errors identify the offending token or end of input with a one-based byte
position in the reported expression. Positions count UTF-8 bytes, as Lua 5.1 and Neovim do, but diagnostics
are one-based while Neovim cursor columns are zero-based. `tokenize` retains its token records
and returns optional span metadata as its third result; `parse_predicate` accepts
that metadata, or falls back to token indices when omitted.

## Editing existing tables

Tables must have unique nonempty headings, rectangular rows, and Boolean cells
in one consistent encoding: `0/1` or `F/T`. Invalid tables produce errors before
buffer edits. Expansion preserves encoding and skips headings already present;
it still validates the expressions and their references against the input table.

Computed columns contain stored values. Dropping a variable leaves those values
intact. Positional references read stored values from an existing column:

```vim
:TruthTableExpand not :h1
```

`:h1` refers to the first column, `:h2` to the second, and so on. If the first
heading is `A ∧ B`, this reads its stored values even after the original variable
columns have been dropped. `not (A and B)` instead evaluates the formula and
requires both variable columns.

Indices resolve against the table before expansion; newly appended columns can
be referenced in the next command. Removing or reordering columns changes their
indices. Generated headings use the resolved label, for example `¬“A ∧ B”`.

References require a positive, in-range index and are unavailable during new-table
construction. Named bracket and backtick references are not supported. Empty
expressions are rejected.

Discovery isolates adjacent tables at their heading/separator pairs and skips
backtick/tilde fenced code and indented code. It supports top-level tables with
uniform indentation of zero to three spaces and preserves that indentation on
edits. Tables nested in lists or blockquotes are outside this supported subset.

Pipes, backslashes, and backticks in headings round-trip through Markdown
escaping, preserving literal reference labels in rendered tables. A table
with no data rows cannot persist its encoding in Markdown; reading it back
uses bits.

## De Morgan refactoring

Put the cursor on an expression-only line, or anywhere in a truth-table column,
and run `:TruthTableDeMorgan`. Virtual text shows the rewritten expression; run
it again to dismiss the preview, even after moving the cursor. `:TruthTableApply` replaces the expression or
selected header (`:TruthTableDeMorganApply` is an alias). Indentation is preserved. Table separator and data lines remain
unchanged, and a heading collision is rejected.

```text
¬(A ∧ B)  ⇒  ¬A ∨ ¬B
¬(A ∨ B)  ⇒  ¬A ∧ ¬B
¬A ∨ ¬B   ⇒  ¬(A ∧ B)
¬A ∧ ¬B   ⇒  ¬(A ∨ B)
```

Which match is rewritten? The nearest one around the cursor: the candidates run
from the smallest group containing the cursor out to the whole expression, so in
`R ∧ (T ∨ E) ∧ (¬T ∨ ¬E)` a cursor on `¬T` gives `R ∧ (T ∨ E) ∧ ¬(T ∧ E)`, and
in `¬(¬A ∨ ¬B)` the cursor chooses between the inner pair and the outer negation.
From a table's data rows there is no cursor in the heading, so the whole heading
is the one candidate. Surrounding parentheses are transparent. Each step is
binary: `¬A ∨ ¬B ∨ C` contracts to `¬(A ∧ B) ∨ C`. The preview
is per buffer and becomes invalid after any buffer edit. Applying a table rewrite
renames its label: update explicit references to the old heading yourself. Stored
column values remain unchanged. Output uses the predicate language's logic symbols;
double negations are retained; there is no automatic simplification.

## Rewrites and derivations

`:TruthTableKarnaugh` gives a simplified sum of products, and the form you want in
code is often one algebra step away from it. Four rewrites take that step on
the operand under the cursor, each previewed the way De Morgan is:

| Command | Cursor on | Example |
|---|---|---|
| `:TruthTableFactor` | an operand several terms share | `S ∨ (A ∧ ¬C) ∨ (G ∧ ¬C)` ⇒ `S ∨ (¬C ∧ (A ∨ G))` |
| `:TruthTableDistribute` | an operand beside a parenthesised group | `¬C ∧ (A ∨ G)` ⇒ `¬C ∧ A ∨ ¬C ∧ G` |
| `:TruthTableCommute` | any operand | `S ∨ (¬C ∧ (A ∨ G))` ⇒ `(¬C ∧ (A ∨ G)) ∨ S` |
| `:TruthTableXor` | either of two complementary terms | `R ∧ ((¬T ∧ E) ∨ (T ∧ ¬E))` ⇒ `R ∧ (T ⊕ E)` |

So, which operand does the cursor pick? A run of one operator out of `∧`, `∨`,
`⊕`, `⇔` is read as a flat list (a *chain*), whatever its parentheses, and the
target is the smallest chain member containing the cursor. On `¬C` the target is
`¬C`; on the `∧` or a parenthesis of `(A ∧ ¬C)` it is that whole group. The
operators of the outermost chain select nothing, and the command says so. In a
table, put the cursor on the heading row, inside the cell.

- Factor works for `∧` inside `∨` and for `∨` inside `∧`. The factor goes on the
left and the remainders are grouped in parentheses. Terms match by shape,
operand order included, so `A ∧ B` and `B ∧ A` need a commute first.
- Distribute multiplies the target into the group directly to its right, or
failing that directly to its left.
- Commute swaps with the operand to the right; `:TruthTableCommute!` swaps to
the left. At the end of a chain the direction flips.
- Xor reads `¬A ∧ B ∨ A ∧ ¬B` as `A ⊕ B` and `A ∧ B ∨ ¬A ∧ ¬B` as `A ⇔ B`, along
with the product-of-sums spellings `(A ∨ B) ∧ (¬A ∨ ¬B)` and
`(¬A ∨ B) ∧ (A ∨ ¬B)`. The cursor can be anywhere in either term. Both terms
have exactly two operands, so factor a shared operand out first:
`¬T ∧ E ∧ R ∨ T ∧ ¬E ∧ R` becomes `R ∧ (¬T ∧ E ∨ T ∧ ¬E)`, then `R ∧ (T ⊕ E)`.
Beside other terms the result is parenthesised, since `⊕` and `⇔` bind
looser than `∨`: `(A ⊕ B) ∨ A ∧ C`.

A preview can land in two ways. `:TruthTableApply` replaces the expression in
place. `:TruthTableApplyStep` leaves the line alone and inserts the rewrite below
it as the next line of a derivation, then moves the cursor there:

```text
S ∨ (A ∧ ¬C) ∨ (G ∧ ¬C) ≡ S ∨ A ∧ ¬C ∨ G ∧ ¬C
≡ S ∨ ¬C ∧ (A ∨ G)
≡ ¬C ∧ (A ∨ G) ∨ S
```

`≡` separates the sides of a derivation: a rewrite reads the side under the
cursor and leaves the others as they are, and a new step lines up under the
line's last `≡` (or at its indentation when it has none). Type it as `equiv@`.
`≡` is outside the predicate language, so `=` keeps its one meaning as a
spelling of `⇔`. Steps apply to expression lines; a heading takes
`:TruthTableApply` only. Both apply commands serve De Morgan previews too.

N.B. the rewrites rearrange an expression and stop there: simplification
(absorption, idempotence, double negation) is yours to do. An in-place apply
re-renders the whole side in logic symbols, as De Morgan does. A formula line
written by an earlier version, `F = …`, reads as one biconditional; change its
`=` to `≡` before stepping from it.

## Karnaugh maps

Put the cursor in a column and run `:TruthTableKarnaugh`. Below the table you
get a Karnaugh map of that column and a simplified sum-of-products formula for it,
rendered in the predicate language so you can paste it straight back into
`:TruthTableExpand` to check it:

```markdown
|  A  |  B  |  C  |  F  |
|:---:|:---:|:---:|:---:|
|  0  |  0  |  0  |  0  |
|  0  |  0  |  1  |  0  |
|  0  |  1  |  0  |  1  |
|  0  |  1  |  1  |  1  |
|  1  |  0  |  0  |  1  |
|  1  |  0  |  1  |  1  |
|  1  |  1  |  0  |  0  |
|  1  |  1  |  1  |  1  |

Karnaugh map for F:

|     |     |     | BC  |     |     |
|:---:|:---:|:---:|:---:|:---:|:---:|
|     |     | 00  | 01  | 11  | 10  |
|  A  |  0  |  0  |  0  |  1  |  1  |
|     |  1  |  1  |  1  |  1  |  0  |

F ≡ ¬A ∧ B ∨ A ∧ ¬B ∨ A ∧ C
```

Which columns are the inputs? The shortest run of columns, starting from the
left, that tells every row apart. For an unmodified table built by `:TruthTable`, this prefix is the variable
columns, so computed columns following them are excluded. Input discovery uses
the current rows and column order, not the history of how a column was created.
After dropping or rearranging columns, the inferred prefix may include computed
columns. Keep the intended variable columns together at the left of the table. Input patterns no row supplies are don't-cares: they
show as `X` in the map and the minimizer may use them. Two rows that agree on
every input but disagree on the target are an error, since the column is then
not a function of those inputs.

The map follows the textbook layout: the last two inputs run across the
columns in Gray order (`00 01 11 10`), the rest down the rows. Maps are drawn
for two to four inputs; with one input or more than four, only the formula is
inserted. The minimizer uses Quine–McCluskey prime implicants, selects essential primes,
and searches for a cover with the fewest terms, then the fewest literals. Exact
cover search has a budget; beyond it, a greedy fallback produces a valid cover
without guaranteeing minimality.

Ties between equally small covers are broken toward the terms that
sort first with literals before free variables, so the output is stable, but
your textbook may list a different, equally minimal answer. Input headings that
are not variable identifiers use positional references (`:hN`) in the formula.

## Tutorial

`:TruthTableTutor` opens a short logic course in a new tab: from propositions
and truth tables through De Morgan, the distributive laws, derivations, and
Karnaugh maps, ending with a condition from code refactored step by step.

The tab has two panes. The lesson pane, on the left, shows one step at a time:
the lesson's aim, what to do, and what you should see afterwards. The scratch
pane, on the right, holds that step's starting text, and is where you run the
commands:

```text
# 3. Connectives: not, and, or            │ p and q | p or q | not p
│
Lesson 3 of 12, step 1 of 2               │
│
**Aim:** Combine propositions with        │
`not`, `and` and `or`, and read the       │
result off a table.                       │
│
... then run `:.TruthTable` on the line.  │
│
You should see:                           │
│
|  p  |  q  | p ∧ q | p ∨ q | ¬p  |       │
|:---:|:---:|:-----:|:-----:|:---:|       │
```

`:TruthTableTutorNext` and `:TruthTableTutorPrev` move one step (`]]` and `[[`
inside the tutor), and `:TruthTableTutor 5` jumps to lesson 5. Every step keeps
its own scratch buffer, so edit freely: `u` undoes back to the starting text,
and your work is still there when you return to a step. Running
`:TruthTableTutor` again brings you back to your place from anywhere;
`:TruthTableTutor!` starts the course over.

The course is data: one Lua table per lesson in `tutor/truth-table/`, read in
file-name order. A lesson is a `title`, an `aim`, and a list of `steps`, each
with its `text`, the scratch pane's `template`, the `expect`ed result, a `note`
on it, and the `solution` that the test suite replays.

## Keymaps

`setup()` registers these by default:

| Key | Action |
|---|---|
| `<leader>ttn` | run `:TruthTable` on the current line, or prefill `:TruthTable ` when it is blank |
| `<leader>ttn` (visual) | run `:TruthTable` on the selected lines |
| `<leader>tte` | prefill `:TruthTableExpand ` |
| `<leader>ttd` | toggle De Morgan preview |
| `<leader>ttf` | toggle factor preview |
| `<leader>ttx` | toggle distribute preview |
| `<leader>tto` | toggle xor-recognition preview |
| `<leader>tts` | toggle commute preview (swap with the next operand) |
| `<leader>ttS` | toggle commute preview (swap with the previous operand) |
| `<leader>tta` | apply the preview in place |
| `<leader>ttA` | apply the preview as a `≡` step |
| `<leader>ttt` | toggle `0/1 ↔ F/T` |
| `<leader>ttr` | drop row |
| `<leader>ttc` | drop column |
| `<leader>ttk` | Karnaugh map and formula for the column |

## Abbreviations

Abbreviations are global across buffers and filetypes. The default trigger is
`@`: type `and@` followed by a space to insert `∧`. `Ctrl-]` expands without
adding a character. Plain words such as `and` in prose stay unchanged.

`abbreviations.symbols` is keyed by the ASCII word you type, using lowercase
names—not constants such as `IMPLIES` or Unicode characters. These are all the
built-in keys:

| Configuration key (symbol) | Default inserted text | Meaning                |
|----------------------------|-----------------------|------------------------|
| `not`                      | `¬`                   | Negation               |
| `and`                      | `∧`                   | Conjunction            |
| `or`                       | `∨`                   | Disjunction            |
| `xor`                      | `⊕`                   | Exclusive or           |
| `implies`                  | `→`                   | Implication            |
| `iff`                      | `⇔`                   | Equivalence            |
| `forall`                   | `∀`                   | Universal quantifier   |
| `exists`                   | `∃`                   | Existential quantifier |
| `true`                     | `⊤`                   | Truth / top            |
| `false`                    | `⊥`                   | Falsity / bottom       |
| `equiv`                    | `≡`                   | Derivation separator   |

The built-in symbol table supplies both default abbreviations and generated
headings. Custom abbreviation settings affect inserted text only.
The quantifier, truth, and `≡` symbols are typing aids; the predicate language
does not accept them as operators or literals.

## Customization

Configure abbreviations through `setup()`. With lazy.nvim, specify the module
explicitly and pass options:

```lua
return {
    "cds-io/truth-table.nvim",
    lazy = false,
    main = "truth-table",
    opts = {
        abbreviations = {
            trigger = ";",          -- type and; rather than and@
            symbols = {             -- configuration keys: not, and, or, xor, etc
                implies = "⇒",        -- change the inserted symbol
                forall = false,       -- disable this abbreviation
                top = "⊤",            -- add top;
            },
        },
    },
}
```

Unspecified keys retain their defaults. A string overrides the inserted text;
`false` disables that abbreviation. Custom ASCII identifier keys are also valid:
`top = "⊤"` adds a new abbreviation and does not replace the built-in `true`.
The built-in keys `not`, `and`, `or`, `true`, and `false` are Lua keywords and
require bracket syntax:

```lua
symbols = {
    ["true"] = false,        -- disable true@ (or true; with trigger = ";")
    ["false"] = false,       -- disable false@
    ["not"] = "¬",
    ["and"] = "∧",
    ["or"] = "∨",
    top = "⊤",              -- add a custom name
}
```

To disable abbreviations, use `opts = { abbreviations = false }`. Without a
plugin manager, call `require("truth-table").setup({ abbreviations = false })`
after adding the plugin to your runtimepath. Automatic loading preserves that
configuration. See [Abbreviations](#abbreviations) for the
built-in keys.

These settings change inserted text, not generated headings or the parser's
accepted operators. Generated headings use Unicode. There is no ASCII-output
mode or configurable parser-alias option.

`symbols` merges over the defaults, which `require("truth-table.abbreviations").defaults`
exposes as `{ trigger = "@", symbols = { ... } }`. Overriding a symbol here
changes what you type, and only that; headings still render from
`truth-table.symbols`. Explicit `setup()` calls replace the plugin-owned
abbreviations. Automatic plugin loading preserves configuration already supplied
in your init file. Disabling or reconfiguring restores displaced global
abbreviations and leaves user replacements made after setup intact. Options are validated before abbreviations are changed.
The trigger must be a single ASCII punctuation character other than backslash,
`|`, `<`, or `>`. Symbol keys must be ASCII identifiers; values must be `false`
or nonempty single-line strings without surrounding whitespace.

## Advanced: wrapping the tokenizer

There is no built-in parser-alias option. The following wrapper depends on the
current module exports and how the core facade captures the tokenizer; check
those details when upgrading.

For example, to accept `≠` as another spelling of XOR and insert it with `xor@`:

```lua
return {
    "cds-io/truth-table.nvim",
    lazy = false,
    opts = { abbreviations = { symbols = { xor = "≠" } } },
    config = function(_, opts)
        require("truth-table").setup(opts)

        local predicate = require("truth-table.predicate")
        local tokenize = predicate.tokenize
        predicate.tokenize = function(input)
            return tokenize((input:gsub("≠", "⊕")))
        end
        -- The core facade captured the original tokenizer when it loaded.
        require("truth-table.core").tokenize = predicate.tokenize
    end,
}
```

> This is an advanced tokenizer wrapper, not a built-in alias setting. Both symbols
> occupy three UTF-8 bytes, so substitution preserves diagnostic byte positions.
> Headings still render XOR as `⊕`. The textual substitution also affects quoted
> column labels containing `≠`; avoid those labels with this wrapper. Quantifier
> and truth-symbol abbreviations (`∀`, `∃`, `⊤`, `⊥`) are typing aids and are not
> currently accepted as predicate operators or literals.

## Compatibility with the original config module

The plugin separates predicate logic, the table model, Markdown formatting, and
Neovim integration. Compared with the original `truth-table.lua` and
`truth-table-core.lua` configuration modules:

- `toggle_cells` returns fresh rows instead of mutating its argument.
- Repeated expansion skips an existing heading instead of appending a duplicate.
- Equivalence renders as `⇔` in generated headings; `=` is still accepted as
an input spelling.
- Parsing, editing, and `format_table` reject malformed/non-Boolean tables with
`nil, error`. Headings must be single-line strings without surrounding whitespace.
- Empty expressions between delimiters now return errors instead of being ignored.

## Design

The logic modules are pure Lua 5.1. The editor and preview adapters use `vim.*`.

- `core.lua` composes construction and expansion and preserves the public APIs.
- `predicate.lua` owns parsing, binding, evaluation, and heading rendering.
Operator definitions share aliases, precedence, symbols, and Boolean semantics.
Binding and variable discovery share a pure post-order AST traversal.
- `table_model.lua` owns numeric Boolean cells, display encoding, validation, and
immutable row/column transformations. Column appending centralizes deduplication.
- `markdown.lua` parses and renders tables. It accepts display-width measurement
explicitly; `core.display_width` retains the existing injection API.
- `karnaugh.lua` finds a column's input variables, minimizes it (Quine-McCluskey
prime implicants, essential primes, then a smallest exact cover under a search
budget, greedy beyond it) and renders the map and the formula.
- `result.lua` composes Lua's `value, error` convention with `bind` and `traverse`.
Only `nil` means failure; zero and false remain successful values.
- `rewrite.lua` finds the chain operand under a cursor byte and factors,
distributes, or commutes it, recognises `⊕`/`⇔` in a pair of terms, and
applies De Morgan at the nearest match: located trees in, fresh trees out.
- `derivation.lua` splits a line into sides at `≡`, replaces one side, and
builds an aligned step line.
- `preview.lua` resolves the expression under the cursor (one side of a line,
or a heading), runs a rewrite on it, and manages per-buffer previews,
extmarks, invalidation, and applying in place or as a step.
- `tutor.lua` reads the lessons in `tutor/truth-table/` and shows them in two
panes, the lesson beside a scratch buffer per step; `tutor_page.lua` (pure)
turns a step into the lesson pane's text. `spec/tutor.lua` replays every
step's `solution` in its scratch buffer and requires the result to be the
step's own `expect` block, so the course stays true as the plugin changes.
- `symbols.lua` is the one table of logic symbols, each an ASCII word plus its
Unicode character; `predicate.lua` renders from it.
- `abbreviations.lua` derives the default insert-mode abbreviations from
`symbols.lua`, merges the `setup()` option over them, and swaps the
registered set on each call.
- `init.lua` registers commands and mappings, reads the buffer, composes parse → transform → render, and applies a
complete result. Editor line ranges stay outside the table model.

The semantic API is `build_model`, `parse_model`, `expand_model`,
`drop_model_row`, `drop_model_column`, `toggle_model`, and `format_model`.
Semantic tables carry numeric `0/1` cells and `encoding = "bits"` or `"tf"`.
Existing string-cell APIs remain compatibility adapters.

## Testing

Run the complete local check (requires Busted, Neovim, and Selene):

```sh
make check
```

The pure core is covered by [busted](https://lunarmodules.github.io/busted/)
specs in `spec/`:

```sh
make test
```

The Makefile prefers `~/.luarocks/bin/busted` when present, then falls back to
`busted` on PATH. This avoids stale Homebrew launchers after Lua upgrades.
If needed, install a user launcher or select one explicitly:

```sh
luarocks --local install busted
make check BUSTED=/path/to/busted
```

Run `make test-integration` for headless Neovim command checks, malformed-table
buffer preservation, rewrite preview/apply behavior, the tutorial's exercises,
and automatic startup.
Lint (optional when running individual checks, requires [selene](https://github.com/Kampfkarren/selene)):

```sh
make lint
```
