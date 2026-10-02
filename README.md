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
(`truth-table.lua` + `truth-table-core.lua`). Behavior is preserved; the
extraction reworked the structure into a pure, testable core plus a thin
Neovim layer.

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
| `:TruthTable {N\|names}` | Insert a new table: `N` variables (A, B, ...) or named ones |
| `:TruthTable {exprs}` | Insert a new table from expressions separated by `\|` or `,`: the variables they mention, plus a computed column per expression |
| `:[range]TruthTable` | Same, reading the argument from the selected lines (a line break is one more `\|`) and replacing them with the table |
| `:TruthTableExpand {preds}` | Append a computed column per comma-separated predicate |
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
Each operator can be typed as its symbol, so a rendered heading parses back to the expression it came from.

Parse errors identify the offending token or end of input with a one-based byte
position in the reported expression. Positions count UTF-8 bytes, matching Lua
5.1 and Neovim buffer column conventions. `tokenize` retains its token records
and returns optional span metadata as its third result; `parse_predicate` accepts
that metadata, or falls back to token indices when omitted.

## Keymaps

`setup()` registers these by default:

| Key | Action |
|---|---|
| `<leader>ttn` | prefill `:TruthTable ` |
| `<leader>ttn` (visual) | run `:TruthTable` on the selected lines |
| `<leader>tte` | prefill `:TruthTableExpand ` |
| `<leader>ttt` | toggle `0/1 ↔ F/T` |
| `<leader>ttr` | drop row |
| `<leader>ttc` | drop column |

## Design

All logic is pure Lua 5.1; only the editor adapter uses `vim.*`.

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
- `init.lua` reads the buffer, composes parse → transform → render, and applies a
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
new columns can be referenced in the next command. Backticks cannot occur inside
a reference, and references are unavailable during new-table construction.
Commas inside references belong to the label. Empty expressions are rejected.

Discovery isolates adjacent tables at their heading/separator pairs and skips
backtick/tilde fenced code and indented code. It supports top-level tables with
uniform indentation of zero to three spaces and preserves that indentation on
edits. Tables nested in lists or blockquotes are outside this supported subset.

Pipes and backslashes in headings round-trip through Markdown escaping. A table
with no data rows cannot persist its encoding in Markdown; reading it back
uses bits.

### Compatibility changes

- `toggle_cells` returns fresh rows instead of mutating its argument.
- Repeated expansion skips an existing heading instead of appending a duplicate.
- Parsing, editing, and `format_table` reject malformed/non-Boolean tables with
  `nil, error`. Headings must be single-line strings without surrounding whitespace.
- Empty expressions between delimiters now return errors instead of being ignored.

## Testing

The pure core is covered by a [busted](https://lunarmodules.github.io/busted/)
spec in `spec/`:

```sh
make test
```

If your `busted` launcher is broken (a common symptom of a Homebrew Lua version
bump: it hard-codes a now-missing `lua5.4`), install busted into your user rocks
tree and point the target at it:

```sh
luarocks --local install busted
make test BUSTED=$HOME/.luarocks/bin/busted
```

Run `make test-integration` for headless Neovim checks of toggle/expand and
malformed-table buffer preservation. Lint (optional, requires [selene](https://github.com/Kampfkarren/selene)):

```sh
make lint
```

## Documentation

`:help truth-table` once the plugin is on your runtimepath.
