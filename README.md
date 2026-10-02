# truth-table.nvim

Generate and manipulate markdown truth tables from inside Neovim.

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

## Install

With lazy.nvim:

```lua
{ dir = "~/dev/nvim-plugins/truth-table.nvim" }
```

The plugin self-registers on load (`plugin/truth-table.lua` calls `setup()`),
so there is nothing else to wire up. which-key is optional (a `<leader>tt`
group label is registered if it is present).

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
| `iff` / `=` / `<->` / `<=>` / `⇔` / `↔` | equivalence | `=` |

Binary operators associate to the left, including implication. Use parentheses
for `A -> (B -> C)`. Parentheses override precedence: `(A or B) and !C`.
Each operator can be typed as its symbol, so a decoded heading parses back to
the expression it came from. Markdown source escapes literal backticks, pipes,
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

## Keymaps

`setup()` registers these by default:

| Key | Action |
|---|---|
| `<leader>ttn` | prefill `:TruthTable ` |
| `<leader>ttn` (visual) | run `:TruthTable` on the selected lines |
| `<leader>tte` | prefill `:TruthTableExpand ` |
| `<leader>ttd` | toggle De Morgan preview |
| `<leader>tta` | apply De Morgan preview |
| `<leader>ttt` | toggle `0/1 ↔ F/T` |
| `<leader>ttr` | drop row |
| `<leader>ttc` | drop column |

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
- `result.lua` composes Lua's `value, error` convention with `bind` and `traverse`.
  Only `nil` means failure; zero and false remain successful values.
- `preview.lua` manages per-buffer De Morgan previews, extmarks, invalidation,
  and applying a rewrite to a line or header.
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
intact. Backticks explicitly reference an existing column by its exact heading:

```vim
:TruthTableExpand not `A ∧ B`
```

This works after A or B is dropped. `not (A and B)` instead evaluates the formula
and requires both variable columns. References bind to positions before expansion;
new columns can be referenced in the next command. Double a backtick inside a
reference to include it in the column name:

```vim
:TruthTableExpand not `¬``A```
```

This reads the stored column named ¬`A`. Backslashes remain literal inside
references. References are unavailable during new-table construction.
Commas inside references belong to the label. Empty expressions are rejected.

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
