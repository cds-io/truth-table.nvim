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
    dependencies = {
        { "blackhat-7/vellum.nvim", optional = true },
    },
}
```

The plugin registers commands and default mappings automatically. Eager
loading makes the global insert-mode abbreviations available at startup;
command-based lazy loading registers them when the plugin first loads.

Two other plugins are optional. Each is used when it is installed, and the
plugin works the same without it:

| Plugin | What it adds |
|---|---|
| [which-key.nvim](https://github.com/folke/which-key.nvim) | a group label for the `<leader>tt` keys, and the keys registered family by family, for a popup that lists them in that order (see [Keymaps](#keymaps)) |
| [vellum.nvim](https://github.com/blackhat-7/vellum.nvim) | the [tutorial](#tutorial)'s lesson pane rendered, where it otherwise shows the lesson's Markdown |

The `dependencies` entry above is how the spec says "vellum, if you have it".
lazy.nvim drops an entry marked `optional = true` unless the same plugin has a
spec of its own somewhere in your config, so on its own it installs nothing.
To get the rendered lesson pane, give vellum that spec (it needs Neovim 0.12
or later, Node.js for diagrams, and has its own
[install notes](https://github.com/blackhat-7/vellum.nvim#install)):

```lua
return {
    "blackhat-7/vellum.nvim",
    ft = "markdown",
    opts = {},
}
```

| Your config has | vellum |
|---|---|
| the `optional = true` entry alone | stays uninstalled; the lesson pane shows Markdown |
| the entry and vellum's own spec | loads when this plugin does, which with `lazy = false` is at startup |
| vellum's own spec alone, with the entry removed | loads the first time the tutor draws a lesson (or on vellum's own triggers) |

N.B. the third row works because the tutor asks for vellum only when it draws
a lesson, and lazy.nvim loads a plugin the first time one of its modules is
required. Take the entry out if you want vellum to keep the lazy-loading its
own spec gives it.

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

Place the cursor on `¬C` and run `:TruthTableFactor`. The preview shows the
result and the law that justifies it:

```text
⇒ S ∨ (¬C ∧ (A ∨ G))  | by distributivity (factoring)
```

Use `:TruthTableApply` to replace the expression, or `:TruthTableApplyStep` to
keep it and insert the equivalent expression, with its law, as the next
derivation step.

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
| `:TruthTableSimplify` | Toggle a preview that applies the collapsing law nearest the cursor (complement, identity, domination, idempotence, absorption, reduction) |
| `:TruthTableApply` | Apply the pending preview in place (`:TruthTableDeMorganApply` is an alias) |
| `:TruthTableApplyStep` | Insert the pending preview below the line as a `≡` derivation step, with its `\| by` justification |
| `:TruthTableRewrites` | List every rewrite of the expression under the cursor, and write the one you pick as a `≡` step (in place, for a table heading) |
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
order: `:TruthTable b | a | a -> b` puts `b` first. (The operator keywords and
the words `true` and `false` are reserved: `:TruthTable p or q` is the
expression `p ∨ q`.)

## Predicate language

Used by `:TruthTableExpand` and the expression form of `:TruthTable`. Operands
are column names and the constants `0` / `1`, which can also be written `⊥` /
`⊤`. A heading keeps whichever of those you typed; the words `false` / `true`
are read too, and rendered as `⊥` / `⊤`. Operators, tightest binding first:

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

Whatever you type, the plugin writes an expression back in one *canonical
form* (the single text that every grouping and parenthesisation of an
expression is rendered as), in headings, previews and derivation steps alike.
The rule is short: an operand that is itself a binary expression gets
parentheses, a run of `∧` or of `∨` is written flat, and no other parenthesis
is written.

| Typed | Rendered | Why |
|---|---|---|
| `a and b or c` | `(a ∧ b) ∨ c` | a mix of operators reads without recalling the binding order |
| `((a)) and (not (b))` | `a ∧ ¬b` | parentheses nothing needs are dropped |
| `(a and b) and c` | `a ∧ b ∧ c` | a run of `∧` or of `∨` means the same however it is grouped |
| `a and (b and c)` | `a ∧ b ∧ c` | so every grouping of the run gets the one flat text |
| `a iff b iff c` | `(a ⇔ b) ⇔ c` | a flat run of `⇔` or `⊕` misreads: `a ⇔ b ⇔ c` is true when `a` is true and the other two are false |
| `a implies b implies c` | `(a → b) → c` | `→` is not associative, so a nested one is always marked |

So two spellings of one expression get one heading, and `:TruthTableExpand`
treats them as the same column. `trees.canonical(ast)` is the tree
transform behind it: it returns one tree for every grouping, with a run of `∧`
or `∨` nested to the left.
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
column values remain unchanged. Output is in canonical form;
double negations are retained (`:TruthTableSimplify` removes one on request).

## Rewrites and derivations

`:TruthTableKarnaugh` gives a simplified sum of products, and the form you want in
code is often one algebra step away from it. Five rewrites take that step at
the cursor, each previewed the way De Morgan is, with the name of the law it
applies:

| Command | Cursor on | Example |
|---|---|---|
| `:TruthTableFactor` | an operand several terms share | `S ∨ (A ∧ ¬C) ∨ (G ∧ ¬C)` ⇒ `S ∨ (¬C ∧ (A ∨ G))` |
| `:TruthTableDistribute` | an operand beside a parenthesised group | `¬C ∧ (A ∨ G)` ⇒ `(¬C ∧ A) ∨ (¬C ∧ G)` |
| `:TruthTableCommute` | any operand | `S ∨ (¬C ∧ (A ∨ G))` ⇒ `(¬C ∧ (A ∨ G)) ∨ S` |
| `:TruthTableXor` | either of two complementary terms | `R ∧ ((¬T ∧ E) ∨ (T ∧ ¬E))` ⇒ `R ∧ (T ⊕ E)` |
| `:TruthTableSimplify` | anywhere; the nearest match wins | `(A ∧ B) ∨ (¬A ∧ B)` ⇒ `B` |

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
- Xor reads `(¬A ∧ B) ∨ (A ∧ ¬B)` as `A ⊕ B` and `(A ∧ B) ∨ (¬A ∧ ¬B)` as
`A ⇔ B`, along with the product-of-sums spellings `(A ∨ B) ∧ (¬A ∨ ¬B)` and
`(¬A ∨ B) ∧ (A ∨ ¬B)`. The cursor can be anywhere in either term. Both terms
have exactly two operands, so factor a shared operand out first:
`(¬T ∧ E ∧ R) ∨ (T ∧ ¬E ∧ R)` becomes `R ∧ ((¬T ∧ E) ∨ (T ∧ ¬E))`, then
`R ∧ (T ⊕ E)`. Beside other terms the result is parenthesised, like any
operand with an operator of its own: `(A ⊕ B) ∨ (A ∧ C)`.

### Simplify

The first four rewrites rearrange an expression. `:TruthTableSimplify`
(`<leader>ttz`) shrinks it: one run applies one *collapsing law* (a law whose
right-hand side is smaller than its left) and the preview says which.

| Law, as the preview names it | Example |
|---|---|
| complement | `A ∨ ¬A` ⇒ `1`, `A ∧ ¬A` ⇒ `0` |
| domination | `A ∨ 1` ⇒ `1`, `A ∧ 0` ⇒ `0` |
| identity | `A ∨ 0` ⇒ `A`, `A ∧ 1` ⇒ `A` |
| idempotence | `A ∨ A` ⇒ `A`, `(A ∧ B) ∨ (B ∧ A)` ⇒ `A ∧ B` |
| absorption | `A ∨ (A ∧ B)` ⇒ `A`, `A ∨ (¬A ∧ B)` ⇒ `A ∨ B`, and the duals |
| reduction | `(A ∧ B) ∨ (¬A ∧ B)` ⇒ `B`, `(A ∨ B) ∧ (¬A ∨ B)` ⇒ `B` |
| negation | `¬1` ⇒ `0`, `¬⊥` ⇒ `⊤` |
| double negation | `¬¬A` ⇒ `A` |

So, which law, and where? The nearest match to the cursor, searched in four
rounds:

1. a law that involves the operand under the cursor: on `A` in
   `A ∨ (A ∧ B) ∨ C ∨ (C ∧ D)`, `A` absorbs `A ∧ B` and `C ∧ D` stays;
2. a law anywhere inside what the cursor selects (a cursor on a parenthesis
   selects the group);
3. a law in a chain around the cursor, with any of its operands;
4. a law anywhere in the expression, innermost and leftmost first.

At any one place the laws are tried in the table's order. From a table's data
rows there is no cursor in the heading, so only the fourth round runs. Terms
match as sets of operands here, so `A ∧ B` and `B ∧ A` count as the same term.
A constant typed as `⊤` or `⊥` keeps that spelling when it survives. Chains of
`⊕` and `⇔`, and `→`, are left as they are (`A ⊕ A` stays put).

### Applying a preview

A preview can land in two ways. `:TruthTableApply` replaces the expression in
place. `:TruthTableApplyStep` leaves the line alone and inserts the rewrite below
it as the next line of a derivation, then moves the cursor there:

```text
(a and b) or (not a and b)
≡ b ∧ (a ∨ ¬a)                | by distributivity (factoring)
≡ b ∧ 1                       | by complement
≡ b                           | by identity
```

`≡` separates the sides of a derivation: a rewrite reads the side under the
cursor and leaves the others as they are, and a new step lines up under the
line's last `≡` (or at its indentation when it has none). Type it as `equiv@`.
`≡` is outside the predicate language, so `=` keeps its one meaning as a
spelling of `⇔`. Steps apply to expression lines; a heading takes
`:TruthTableApply` only. Both apply commands serve De Morgan previews too.

Each step ends in its *justification*: `| by` and the law that takes the line
above to this one. The laws are named as in the table above, plus
`distributivity (factoring)` and `distributivity (distributing)` (factoring
moves a shared operand out of its terms and distributing moves one into a
group: the one law, used from either side, with the side named so that a step
says which command wrote it), `commutativity`,
`De Morgan`, and `definition of ⊕` or `⇔`. The bar sits four columns clear of
the wider of the two lines, or under the bar of the line above when that is
further right, so the justifications of a
derivation form a column. Everything from the first `|` of an expression line
on is a remark: a rewrite reads the expression before it, and a cursor in the
remark means the line's last side. Applying in place to a justified line adds
the new law to it (`| by distributivity (factoring), complement`), so the line
still says
how it follows from the one above.

N.B. Simplify takes one step per run and leaves the choice of steps to you; for
a minimal form in one go, build the table and use `:TruthTableKarnaugh`. An
in-place apply re-renders the whole side in canonical form, as De Morgan does. A
formula line written by an earlier version, `F = …`, reads as one
biconditional; change its `=` to `≡` before stepping from it.

### Every rewrite at once

Each command above starts from a law: you choose De Morgan, or factoring, put
the cursor where you think it applies, and the preview tells you whether you
were right. `:TruthTableRewrites` (`<leader>ttl`) starts from the expression.
It lists every rewrite the expression allows, each as its result and the law
that gives it, and writes the one you pick. For `(a and b) or (not a and b)`:

```text
b                                | by reduction
b ∧ (a ∨ ¬a)                     | by distributivity (factoring)
((a ∧ b) ∨ ¬a) ∧ ((a ∧ b) ∨ b)   | by distributivity (distributing)
(a ∨ (¬a ∧ b)) ∧ (b ∨ (¬a ∧ b))  | by distributivity (distributing)
(¬a ∧ b) ∨ (a ∧ b)               | by commutativity
(b ∧ a) ∨ (¬a ∧ b)               | by commutativity
(a ∧ b) ∨ (b ∧ ¬a)               | by commutativity
```

So, what does "every" cover? Every law the plugin has, at every place in the
expression where it applies: the cursor only chooses which expression (a side
of a line, or a table column from any of its rows). That is a little more than
the keys reach, since Simplify shows the one collapsing law nearest the cursor
and the menu shows them all. Three rules keep the list readable:

- A result appears once, under the first law that reaches it (swapping `a`
  with `b` and swapping `b` with `a` are one entry).
- A rewrite that reads the same as the expression is left out (swapping the
  two operands of `A ∧ A`).
- The laws that shrink the expression come first, then De Morgan, `⊕` and `⇔`
  recognition, factoring, distributing, and the swaps, which are the most
  numerous. The shrinking laws are listed innermost place first (the order
  Simplify tries them in) and the others outermost first; all of them left to
  right.

A pick is written at once, with no preview in between. On an expression line
it becomes the next step of the derivation, justified and aligned the way
`:TruthTableApplyStep` writes one, and the cursor moves onto it, so the next
`<leader>ttl` lists the rewrites of the step you just took. A table heading
has no steps, so there the pick renames the heading in place, as
`:TruthTableApply` does. Cancelling the menu writes nothing.

The menu is `vim.ui.select`, so it looks like every other menu in your setup
(telescope, snacks, fzf-lua, or the built-in numbered list); it passes
`kind = "truth-table.rewrite"` for a UI that styles menus by kind.

N.B. The list grows with the expression: a chain of five terms has around two
dozen entries, most of them swaps at the bottom. A picker with fuzzy search
narrows it by law name (`absorp`, `morgan`).

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

F ≡ (¬A ∧ B) ∨ (A ∧ ¬B) ∨ (A ∧ C)
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
and truth tables through the laws of Boolean algebra (the constant and
complement laws, De Morgan, the commutative, associative and distributive laws,
absorption and reduction), derivations, and Karnaugh maps, ending with a
condition from code refactored step by step. The last lesson is a reference
sheet of every law and command.

The course keeps one use in view: refactoring code. A function that returns
true or false, however many `return`s it has, is one Boolean expression
written as control flow (`if (c) return true; rest` is `c ∨ rest`, and
`if (c) return false; rest` is `¬c ∧ rest`), and the lessons practise reading
one that way. Their examples are small functions from application code: a
merge of two branches that a truth table shows to be wrong, negated conditions
turned from reasons to reject into requirements with De Morgan, a distributed
rule factored back, and a retry condition that turns out to be an exclusive
or.

The examples up to that point are JavaScript. Five lessons are all Lua, four
taken from a Neovim config (each excerpt links to its source at a fixed
commit) and one from *Programming in Lua*, to show that a script gains as
much as an application does: four guard clauses
read back as one expression, two negations pulled into one named condition,
the condition an `elseif` runs under worked out in seven steps, and a truth
table for the `c and x or y` idiom, whose truthiness differs in one Boolean
row from the intended ternary (`c ? x : y`) and whose returned values need a
separate check, and a dispatch on type simplified by excluding impossible
type combinations using domain knowledge.

Each of those examples goes through the same five stages, since getting from
code to an expression is a task of its own and so is getting back: name the
checks (the smallest tests, a letter each), translate the code into an
expression, rewrite it or compare it with a table, put the tests back and
write the code, and review the before and after side by side (what the change buys, what it
costs, and whether to take it). Guidance decreases across the Lua lessons:
learners supply names, branch expressions, a verdict, and finally their own
guard-based implementation before comparing it with the worked version.
The verdicts differ: one review declines the rewrite and keeps a comment,
and one calls it a matter of taste.

The tab has two panes. The lesson pane, on the left, shows one step at a time:
the lesson's aim, what to do, and what you should see afterwards. The scratch
pane, on the right, holds that step's starting text, and is where you run the
commands:

```text
# 3. Connectives: not, and, or            │ p and q | p or q | not p
│
Lesson 3 of 19, step 1 of 2               │
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

That picture is the lesson pane showing the step's Markdown. With
[vellum.nvim](https://github.com/blackhat-7/vellum.nvim) installed, the pane
shows the step rendered instead: prose wrapped to the pane's width (100 columns
at most), the title in a band, code in shaded panels with syntax colours, and
inline code set off from the prose, all in your colorscheme's colours. The
pane has no line numbers or sign column, and it is drawn again when its width
or the colorscheme changes.

vellum is optional, and there is nothing to configure. The tutor asks for
vellum's renderer each time it draws a step, and shows the Markdown whenever
that comes back empty-handed:

| vellum.nvim | Lesson pane |
|---|---|
| installed, and it renders the step | the rendered step (filetype `truth-table-tutor`) |
| absent | the step's Markdown (filetype `markdown`) |
| installed, and it raises an error or returns a highlight outside its line | the step's Markdown, with one warning per session giving the reason |

The tutor calls the renderer vellum uses for its own `:Vellum` preview
(`vellum.render`) and paints the result itself, so no preview window opens
and a preview you have open keeps following your own buffers. That module is
internal to vellum, with no promise of staying as it is; the third row of the
table is there for the day it changes. It was tested against vellum v0.2.0
(commit `c9a8665`). Diagrams and pictures are out of scope: the lessons
contain neither.

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

`setup()` registers these by default, in three families:

| Key | Family | Action |
|---|---|---|
| `<leader>ttn` | Table | run `:TruthTable` on the current line, or prefill `:TruthTable ` when it is blank |
| `<leader>ttn` (visual) | Table | run `:TruthTable` on the selected lines |
| `<leader>tte` | Table | prefill `:TruthTableExpand ` |
| `<leader>ttt` | Table | toggle `0/1 ↔ F/T` |
| `<leader>ttr` | Table | drop row |
| `<leader>ttc` | Table | drop column |
| `<leader>ttk` | Table | Karnaugh map and formula for the column |
| `<leader>ttd` | Rewrite | toggle De Morgan preview |
| `<leader>ttf` | Rewrite | toggle factor preview (the operand moves out of its terms) |
| `<leader>ttx` | Rewrite | toggle distribute preview (the operand moves into the group) |
| `<leader>tts` | Rewrite | toggle commute preview (swap with the next operand) |
| `<leader>ttS` | Rewrite | toggle commute preview (swap with the previous operand) |
| `<leader>tto` | Rewrite | toggle xor-recognition preview |
| `<leader>ttz` | Rewrite | toggle simplify preview |
| `<leader>ttl` | Rewrite | list every rewrite and write the one picked |
| `<leader>tta` | Apply | apply the preview in place |
| `<leader>ttA` | Apply | apply the preview as a `≡` step with its justification |

Each keymap's description opens with its family (`Table: new`,
`Rewrite: factor operand out`, `Apply: in place`), so the grouping shows in a
[which-key](https://github.com/folke/which-key.nvim) popup. By default
which-key lists a popup by key, which interleaves the families. To list them
in the order above, add `"manual"` to which-key's `sort` option: it follows
the order mappings were registered in, and the plugin registers its keys
family by family.

```lua
require("which-key").setup({
    sort = { "local", "order", "group", "manual", "alphanum", "mod" },
})
```

`sort` applies to every which-key popup: keys that other plugins register
through which-key will also appear in their registration order.

Factor and Distribute are the one law used from either side, and easy to
reach for the wrong way round. When one refuses and the other applies at the
cursor, the refusal says so: `No neighbouring group to distribute Q into; to
pull it out of the terms that share it, use :TruthTableFactor`.

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
The predicate language reads `⊤` and `⊥` (and the words `true` and `false`) as
the constants `1` and `0`. The quantifiers and `≡` are typing aids, outside the
predicate language.

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
> column labels containing `≠`; avoid those labels with this wrapper. The
> quantifier abbreviations (`∀`, `∃`) are typing aids, outside the predicate
> language.

## Compatibility with the original config module

The plugin separates predicate logic, the table model, Markdown formatting, and
Neovim integration. Compared with the original `truth-table.lua` and
`truth-table-core.lua` configuration modules:

- A table is a model: `headers`, `rows` of 0 and 1, and an `encoding` of
`bits` or `tf` that the Markdown codec spells. `build`, `expand`,
`toggle` and `format` are the API over it.
- Repeated expansion skips an existing heading instead of appending a duplicate.
- Equivalence renders as `⇔` in generated headings; `=` is still accepted as
an input spelling.
- Parsing, editing, and formatting reject malformed/non-Boolean tables with
`nil, error`. Headings must be single-line strings without surrounding whitespace.
- Empty expressions between delimiters now return errors instead of being ignored.

## Design

The logic modules are pure Lua 5.1. The editor and preview adapters use `vim.*`.

- `core.lua` composes construction, expansion and the edits over the model;
it provides the table pipeline used by `init.lua`.
- `predicate.lua` is the language: the tokenizer, the parser, the evaluator,
and the binding of names to row positions. Binding and variable discovery are
written over the copying traversal in `trees.lua`.
- `operators.lua` is the one table of operators: each one's keyword, rendered
symbol, further spellings, binding power and Boolean meaning, read by the
parser, the evaluator and the renderer alike.
- `trees.lua` works on the trees the parser makes: the helpers that take a
chain apart and put one together (`unparen`, `operands`, `fold`), the copying
`transform`, the canonical form of a tree and its text as a heading, and the
whole-expression De Morgan rewrite.
- `table_model.lua` owns numeric Boolean cells, display encoding, validation, and
immutable row/column transformations. Column appending centralizes deduplication.
- `markdown.lua` parses and renders tables. It accepts display-width measurement
explicitly; `core.display_width` retains the existing injection API.
- `karnaugh.lua` finds a column's input variables, minimizes it (Quine-McCluskey
prime implicants, essential primes, then a smallest exact cover under a search
budget, greedy beyond it) and renders the map and the formula.
- `result.lua` composes Lua's `value, error` convention: `bind` and `traverse`
for a step that can refuse, `map` for one that cannot, and `context` to say
where an error was met.
Only `nil` means failure; zero and false remain successful values.
- `fp.lua` is `map`, `filter` and `reduce` over lists, for the pure modules:
plain Lua 5.1 has none of the three, and `vim.iter` needs the editor. Map and
filter return fresh arrays; reduce returns the final accumulator. Each takes
its function last; `map` refuses a `nil` result,
which would leave a hole that `ipairs` stops at.
- `rewrite.lua` finds the chain operand under a cursor byte and factors,
distributes, or commutes it, recognises `⊕`/`⇔` in a pair of terms, applies De
Morgan at the nearest match, and applies the nearest collapsing law
(simplify): located trees in, fresh trees out, each with the name of the law
applied. `moves` lists what all of them give from every place in a tree: each
rewrite is written against an operand's path from the root, which a cursor
byte or a walk of the tree supplies.
- `derivation.lua` splits a line into sides at `≡`, sets its `| by`
justification apart, replaces one side, and builds an aligned, justified step
line.
- `preview.lua` resolves the expression under the cursor (one side of a line,
or a heading), runs a rewrite on it, and manages per-buffer previews,
extmarks, invalidation, and applying in place or as a step. It also shows the
menu of every rewrite (`vim.ui.select`) and writes the pick through the same
two paths.
- `tutor.lua` reads the lessons in `tutor/truth-table/` and shows them in two
panes, the lesson beside a scratch buffer per step; `tutor_page.lua` (pure)
turns a step into the lesson pane's Markdown, and `tutor_vellum.lua` turns
that into styled lines when vellum.nvim is installed (and into nothing when it
is absent or fails, which is `tutor.lua`'s cue to show the Markdown).
`spec/tutor_nvim_spec.lua` replays every
step's `solution` in its scratch buffer and requires the result to be the
step's own `expect` block, so the course stays true as the plugin changes. It
also evaluates every law a lesson states (`left ≡ right` in a fenced block)
over all values of its variables.
- `symbols.lua` is the one table of logic symbols, each an ASCII word plus its
Unicode character; `operators.lua` builds on it.
- `abbreviations.lua` derives the default insert-mode abbreviations from
`symbols.lua`, merges the `setup()` option over them, and swaps the
registered set on each call.
- `init.lua` registers commands and mappings, reads the buffer, composes parse → transform → render, and applies a
complete result. Editor line ranges stay outside the table model.

The API over the model is `build`, `parse`, `expand`, `drop_row`,
`drop_column`, `toggle`, and `format`. A table carries numeric `0/1` cells and
`encoding = "bits"` or `"tf"`.

## Testing

Run the complete local check (requires Busted, nlua, Neovim, and Selene):

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

The specs named `*_nvim_spec.lua` need an editor: they run commands, read
extmarks, type into a buffer, open the tutor's panes. They are busted specs
too, run with Neovim as the Lua interpreter:

```sh
luarocks --lua-version 5.1 --local install nlua
make test-nvim
```

[nlua](https://github.com/mfussenegger/nlua) is a small script that makes
`nvim -l` answer to the command line of the `lua` program, which is what
busted's `--lua` option expects. The pure specs stay under plain Lua
(`make test` skips the `*_nvim_spec.lua` files), so a logic module that
reaches for `vim` still fails there. Three details of the recipe, each of
which fails in its own way when missing:

- busted and nlua are installed for Lua 5.1, the version Neovim's LuaJIT
  implements; a rock built for another Lua version is invisible to it.
- The target takes `LUA_PATH` and `LUA_CPATH` from `luarocks path`, since the
  Neovim process finds busted's own modules through them.
- nlua runs the `nvim` that is first on `PATH`, and after the specs it runs
  whatever arrives on a stdin that is not a terminal as Lua. The target gives
  it an empty stdin; without one, a run whose stdin is a pipe that stays open
  waits on it forever.

Each of those files gets a Neovim of its own (the target runs busted once per
file), so a spec can set the plugin up, replace `vim.notify` and open tabs
without the next file inheriting any of it:

| Spec | Covers | Its cases |
|---|---|---|
| `abbreviations_nvim_spec.lua` | the `abbreviations` option of `setup()` | independent; each starts from the defaults the plugin entry point installs |
| `integration_nvim_spec.lua` | commands and default keymaps, malformed tables left alone | independent; each writes its buffer |
| `preview_nvim_spec.lua` | rewrite previews, applying in place and as a step, headings, refusals, the menu of every rewrite | independent; each in a fresh buffer |
| `tutor_nvim_spec.lua` | the course's shape and laws, the two panes, every exercise replayed | fresh sessions for navigation; one independent case per lesson |
| `tutor_vellum_nvim_spec.lua` | the lesson pane with no vellum, an installed one, and a stand-in | scoped renderer modules; one continuous stand-in lifecycle case |
| `startup_nvim_spec.lua` | Neovim loading `plugin/` by itself | independent |

The startup spec is the odd one: a spec runs inside a Neovim that has already
started, so it starts a second one with `spec/startup_init.lua` as its init
file, once bare and once after `setup({ abbreviations = false })`, and reads
what that Neovim reports about itself.

In the tutor spec a lesson whose replay fails puts the reader on the next
lesson before it gives up, so one wrong lesson is one failed case (the Next
that normally moves the reader on is the last thing a lesson's case does).

The lesson-pane spec uses a stand-in for vellum, so it runs anywhere, and
reports the installed-vellum case as pending. To render every step of the
course through an installed vellum as well, name its directory:

```sh
TRUTH_TABLE_TEST_VELLUM=~/.local/share/nvim/lazy/vellum.nvim make test-nvim
```

Lint (optional when running individual checks, requires [selene](https://github.com/Kampfkarren/selene)):

```sh
make lint
```
