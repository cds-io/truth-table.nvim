return {
    title = "Lua: `and` and `or` as a ternary",
    aim = "Test the `c and x or y` idiom against the ternary it stands in for, and know the one row where they part.",
    steps = {
        {
            text = [[
**Stage 1 of 5: name the checks.**

A *ternary* is an expression that picks one of two values: `c ? x : y` in
JavaScript is `x` when `c` holds and `y` when it does not. Lua has no ternary,
and the idiom that stands in for one is built from `and` and `or`. This
callback receives the answer to a "go to
definition" request, which can be one location or a list of them:

```lua
if err or not result or (type(result) == 'table' and vim.tbl_isempty(result)) then
  vim.notify('No definition under cursor', vim.log.levels.WARN)
  return
end
local loc = vim.islist(result) and result[1] or result
```

Source: https://github.com/cds-amal/kickstart.nvim/blob/2cbd7d2f997a430fc6156eb97865f630961a2f6b/lua/lsp.lua#L112-L116

The last line is meant as "if `result` is a list then its first item, else
`result`". The idiom has three parts, and this time the letters stand for the
parts of a pattern:

```text
c    vim.islist(result)    the condition
x    result[1]             the value wanted when the condition holds
y    result                the value wanted when it fails
```

`x` and `y` are values, where the checks so far were tests. What matters to
`and` and `or` is whether a value counts as true: in Lua everything does,
except `false` and `nil`. So `x` in the table to come means "`x` is neither
`false` nor `nil`".

There is nothing to run in this step.
]],
        },
        {
            text = [[
**Stages 2 and 3 of 5: translate, and compare.**

Two things to translate, the idiom and what it is meant to be:

```text
c and x or y                    the idiom, as written
if c then x else y              the intent
```

The idiom is already an expression. The intent is a ternary, and written out
with the connectives it is `(c ∧ x) ∨ (¬c ∧ y)`: `x` when `c` holds, `y`
when it does not.

Is the idiom the same thing? There is nothing to rewrite here; the question is
whether two expressions agree, and a table answers that. The scratch pane
holds both. Build the table (`:.TruthTable`, `<leader>ttn`).
]],
            template = [[
c and x or y | (c and x) or (not c and y)
]],
            expect = [[
|  c  |  x  |  y  | (c ∧ x) ∨ y | (c ∧ x) ∨ (¬c ∧ y) |
|:---:|:---:|:---:|:-----------:|:------------------:|
|  0  |  0  |  0  |      0      |         0          |
|  0  |  0  |  1  |      1      |         1          |
|  0  |  1  |  0  |      0      |         0          |
|  0  |  1  |  1  |      1      |         1          |
|  1  |  0  |  0  |      0      |         0          |
|  1  |  0  |  1  |      1      |         0          |
|  1  |  1  |  0  |      1      |         1          |
|  1  |  1  |  1  |      1      |         1          |
]],
            note = [[
One row differs: `c` true, `x` false, `y` true. The condition holds, and the
idiom still falls through to `y`, because `c and x` came out false. That is
the whole weakness of the idiom: it is a ternary only as long as `x` can
never be `false` or `nil`.
]],
            solution = {
                { on = "c and x or y | (c and x) or (not c and y)", run = { ".TruthTable" } },
            },
        },
        {
            text = [[
**Stage 4 of 5: back into Lua.**

The table says where to look: the row where the condition holds and `x` is
`false` or `nil`. Put the parts back in place of the letters:

```text
c true, x false or nil      vim.islist(result) holds, and result[1] is nil
```

Can that happen? A list whose first item is `nil` is an empty list. The guard
three lines up returns early when `result` is an empty table, so by the time
this line runs, a list has a first item. The row is closed off, and the line
is right.

The form with no such row is an `if` statement, which is how Lua spells a
ternary in full:

```lua
local loc = result
if vim.islist(result) then
  loc = result[1]
end
```

The same care goes for the order of the operands. Lua's `and` and `or` stop
at the first operand that settles the answer, so in this guard, from the same
config, the first operand protects the second:

```lua
if not command_node or command_node:type() ~= 'command' then
```

Source: https://github.com/cds-amal/kickstart.nvim/blob/2cbd7d2f997a430fc6156eb97865f630961a2f6b/lua/plugins/languages/zsh-utils.lua#L48

Commuting the two is sound as logic, and would call a method on `nil`. The
laws are about truth values; which operand runs first is a second question,
and Lua answers it left to right.

There is nothing to run in this step.
]],
            template = [[
c    vim.islist(result)    the condition
x    result[1]             the value wanted when the condition holds
y    result                the value wanted when it fails

The row where the idiom and the ternary differ:

|  c  |  x  |  y  | (c ∧ x) ∨ y | (c ∧ x) ∨ (¬c ∧ y) |
|:---:|:---:|:---:|:-----------:|:------------------:|
|  1  |  0  |  1  |      1      |         0          |
]],
        },
        {
            text = [[
**Stage 5 of 5: review.**

This is the before and after: the scratch pane holds both. Consider the change
the way a code reviewer would.

What changed, by count:

```text
                                    before    after
lines                                    1        4
rows where it does the wrong thing       1        0
```

What the long form buys:

- **No row to worry about.** It is correct for every value `result[1]` can
  have, whatever the code above it does.
- **It survives a change elsewhere.** The idiom is right only because of the
  guard three lines up. Remove or loosen that guard and the idiom starts
  returning the empty list where a location was expected, with nothing at
  this line to show for it.

What it costs:

- **Three more lines** for something the idiom says in one, in a form every
  Lua reader knows on sight.
- **A variable that is assigned twice**, where the idiom gives `loc` its
  value once.

The verdict: keep the idiom here. It is the common spelling, and the row it
gets wrong is closed off a few lines above. What the table changes is what a
reviewer looks for: every `c and x or y` comes with the question "can `x` be
`false` or `nil`?", and a line such as `enabled and false or default` fails it
at a glance.
]],
            template = [[
Before:

```lua
local loc = vim.islist(result) and result[1] or result
```

After:

```lua
local loc = result
if vim.islist(result) then
  loc = result[1]
end
```
]],
        },
    },
}
