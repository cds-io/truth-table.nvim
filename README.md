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
| `:TruthTableExpand {preds}` | Append a computed column per comma-separated predicate |
| `:TruthTableToggle` | Toggle data cells between `0/1` and `F/T` |
| `:TruthTableDropRow` | Drop the row under the cursor |
| `:TruthTableDropColumn` | Drop the column under the cursor |

```
:TruthTable 3
:TruthTable p q r
:TruthTableExpand A and B, A xor B
```

## Predicate language

Used by `:TruthTableExpand`. Operands are existing column names and the literals
`0` / `1`. Operators, tightest binding first:

| Operator | Meaning | Rendered |
|---|---|---|
| `not` / `!` | negation | `¬` |
| `and` | conjunction | `∧` |
| `or` | disjunction | `∨` |
| `xor` | exclusive or | `⊕` |
| `implies` / `->` | implication | `→` |

Parentheses override precedence: `(A or B) and !C`.

## Keymaps

`setup()` registers these by default:

| Key | Action |
|---|---|
| `<leader>ttn` | prefill `:TruthTable ` |
| `<leader>tte` | prefill `:TruthTableExpand ` |
| `<leader>ttt` | toggle `0/1 ↔ F/T` |
| `<leader>ttr` | drop row |
| `<leader>ttc` | drop column |

## Design

Split along one line, Neovim or not:

- `lua/truth-table/core.lua` is **pure**: the predicate tokenizer/parser,
  evaluator, validation, and markdown formatting, all as plain functions over
  strings and tables with no `vim.*`. The one contextual dependency,
  display-width measurement, is injectable: `core.display_width` defaults to a
  pure UTF-8 codepoint count, and `setup()` swaps in `vim.fn.strdisplaywidth`
  for terminal-accurate alignment (they agree for the ASCII names and width-1
  logic symbols this tool emits).
- `lua/truth-table/init.lua` holds the Neovim-facing pieces (finding the table
  under the cursor, the commands, keymaps) and the public `setup()`.
- `plugin/truth-table.lua` is the auto-sourced entry point with a load guard.

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

The `vim`-coupled layer is verified by loading the plugin and running the
commands. Lint (optional, requires [selene](https://github.com/Kampfkarren/selene)):

```sh
make lint
```

## Documentation

`:help truth-table` once the plugin is on your runtimepath.
