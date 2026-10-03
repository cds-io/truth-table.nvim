# truth-table.nvim

[GitHub: cds-io/truth-table.nvim](https://github.com/cds-io/truth-table.nvim)

Generate and manipulate Markdown truth tables from inside Neovim, natch.

Give it a count or a list of variable names and it writes every combination of
their values as a centered markdown table. Put your cursor in an existing table
and it can append computed columns from a small boolean predicate language,
toggle between `0/1` and `F/T`, or drop the current row or column.

```
|  A  |  B  | A ∧ B | A → B |
|:---:|:---:|:-----:|:-----:|
|  0  |  0  |   0   |   1   |
|  0  |  1  |   0   |   1   |
|  1  |  0  |   0   |   0   |
|  1  |  1  |   1   |   1   |
```

## Status

Personal plugin, extracted from a single-file Neovim config module
(`truth-table.lua` + `truth-table-core.lua`). The current implementation separates
predicate logic, the table model, Markdown formatting, and Neovim integration.
See the compatibility changes below for differences from the original module.

An LLM was used to convert a long time personally maintained hack to a plugin
with testing.

## Install and defaults

With lazy.nvim:

```lua
return {
  "cds-io/truth-table.nvim",
  lazy = false,
}
```

Load it eagerly if you want the global insert-mode abbreviations available from
startup. Loading only on a `TruthTable` command delays abbreviation registration
until that command is used. The plugin registers commands and default mappings
automatically; which-key is optional.

### Default abbreviations

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

The same symbol table supplies default abbreviations and generated headings.
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
Use bracket syntax for Lua keywords, for example:

```lua
symbols = {
  ["true"] = false,        -- disable true@ (or true; with trigger = ";")
  ["false"] = false,       -- disable false@
  ["and"] = "∧",           -- keyword keys require brackets
  top = "⊤",              -- add a custom name
}
```

To disable abbreviations, use `opts = { abbreviations = false }`. Without a
plugin manager, call `require("truth-table").setup({ abbreviations = false })`
after adding the plugin to your runtimepath. Automatic loading preserves that
configuration. See [Default abbreviations](#default-abbreviations) for the
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

### Adding a parser alias

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

## Commands

| Command | Effect |
|---|---|
| `:TruthTable {N\|names}` | Insert a new table above the current line: `N` variables (A, B, ...) or named ones |
| `:TruthTable {exprs}` | Insert a new table from expressions separated by `\|` or `,`: the variables they mention, plus a computed column per expression |
| `:[range]TruthTable` | Same, reading the argument from the selected lines (a line break is one more `\|`) and replacing them with the table |
| `:TruthTableExpand {preds}` | Append a computed column per comma-separated predicate |
| `:TruthTableDeMorgan` | Toggle virtual-text preview for the whole expression line or current column header |
| `:TruthTableDeMorganApply` | Apply the pending rewrite |
| `:TruthTableToggle` | Toggle data cells between `0/1` and `F/T` |
| `:TruthTableDropRow` | Drop the row under the cursor |
| `:TruthTableDropColumn` | Drop the column under the cursor |
| `:TruthTableKarnaugh` | Insert, below the table, a Karnaugh map and a minimal sum-of-products formula for the column under the cursor |

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
expressions. Reference-based headings describe stored values; use positional references to
reference those values again. Markdown source escapes literal backticks, pipes,
and backslashes; use the decoded label when referencing a column.
New-table expressions must mention at least one variable; constant-only
expressions are supported by expansion of an existing table.

Parse errors identify the offending token or end of input with a one-based byte
position in the reported expression. Positions count UTF-8 bytes, as Lua 5.1 and Neovim do, but diagnostics
are one-based while Neovim cursor columns are zero-based. `tokenize` retains its token records
and returns optional span metadata as its third result; `parse_predicate` accepts
that metadata, or falls back to token indices when omitted.

## De Morgan refactoring

Put the cursor on an expression-only line, or anywhere in a truth-table column,
and run `:TruthTableDeMorgan`. Virtual text shows the rewritten expression; run
it again to dismiss the preview, even after moving the cursor. `:TruthTableDeMorganApply` replaces the line or
selected header. Indentation is preserved. Table separator and data lines remain
unchanged, and a heading collision is rejected.

```text
¬(A ∧ B)  ⇒  ¬A ∨ ¬B
¬(A ∨ B)  ⇒  ¬A ∧ ¬B
¬A ∨ ¬B   ⇒  ¬(A ∧ B)
¬A ∧ ¬B   ⇒  ¬(A ∨ B)
```

Only the root expression is transformed; surrounding parentheses are transparent.
Nested-only matches report that no whole-expression rewrite applies. The preview
is per buffer and becomes invalid after any buffer edit. Applying a table rewrite
renames its label: update explicit references to the old heading yourself. Stored
column values remain unchanged. Output uses the predicate language's logic symbols;
double negations are retained; there is no automatic simplification.

## Karnaugh maps

Put the cursor in a column and run `:TruthTableKarnaugh`. Below the table you
get a Karnaugh map of that column and a minimal sum-of-products formula for it,
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
left, that tells every row apart. For a table built by `:TruthTable` that is
the variable columns; a computed column sitting between them and the target is
never treated as an input. Input patterns no row supplies are don't-cares: they
show as `X` in the map and the minimizer may use them. Two rows that agree on
every input but disagree on the target are an error, since the column is then
not a function of those inputs.

The map follows the textbook layout: the last two inputs run across the
columns in Gray order (`00 01 11 10`), the rest down the rows. Maps are drawn
for two to four inputs; with one input or more than four, only the formula is
inserted. Covers minimize the number of terms, then the number of literals.
Ties between equally small covers are broken toward the terms that
sort first with literals before free variables, so the output is stable, but
your textbook may list a different, equally minimal answer. Input headings that
are not variable identifiers use positional references (`:hN`) in the formula.

## Keymaps

`setup()` registers these by default:

| Key | Action |
|---|---|
| `<leader>ttn` | run `:TruthTable` on the current line, or prefill `:TruthTable ` when it is blank |
| `<leader>ttn` (visual) | run `:TruthTable` on the selected lines |
| `<leader>tte` | prefill `:TruthTableExpand ` |
| `<leader>ttd` | toggle De Morgan preview |
| `<leader>tta` | apply De Morgan preview |
| `<leader>ttt` | toggle `0/1 ↔ F/T` |
| `<leader>ttr` | drop row |
| `<leader>ttc` | drop column |
| `<leader>ttk` | Karnaugh map and formula for the column |

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
- `preview.lua` manages per-buffer De Morgan previews, extmarks, invalidation,
  and applying a rewrite to a line or header.
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

### Compatibility changes

- `toggle_cells` returns fresh rows instead of mutating its argument.
- Repeated expansion skips an existing heading instead of appending a duplicate.
- Equivalence renders as `⇔` in generated headings; `=` is still accepted as
  an input spelling.
- Parsing, editing, and `format_table` reject malformed/non-Boolean tables with
  `nil, error`. Headings must be single-line strings without surrounding whitespace.
- Empty expressions between delimiters now return errors instead of being ignored.

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
buffer preservation, De Morgan preview/apply behavior, and automatic startup.
Lint (optional when running individual checks, requires [selene](https://github.com/Kampfkarren/selene)):

```sh
make lint
```

## Documentation

`:help truth-table.txt` once the plugin is on your runtimepath.
