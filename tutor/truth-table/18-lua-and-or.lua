return {
    title = "Lua: `and` and `or` as a ternary",
    aim = "Compare the truthiness and returned values of `c and x or y` with a ternary, then check what makes the idiom safe here.",
    steps = {
        {
            text = [=[
**Stage 1 of 5: name the checks.**

A *ternary* is an expression that picks one of two values: `c ? x : y` in
JavaScript is `x` when `c` holds and `y` when it does not. Lua has no ternary,
and the idiom that stands in for one is built from `and` and `or`. This
callback receives the answer to a "go to
definition" request, which can be one location or a list of them:

```lua
if err or not result
    or (type(result) == 'table' and vim.tbl_isempty(result)) then
  vim.notify('No definition under cursor', vim.log.levels.WARN)
  return
end
local loc = vim.islist(result) and result[1] or result
```

Source: [kickstart.nvim, lua/lsp.lua, lines 112 to 116](https://github.com/cds-amal/kickstart.nvim/blob/2cbd7d2/lua/lsp.lua#L112-L116)

The last line is meant as "if `result` is a list then its first item, else
`result`". The idiom has three parts, and this time the letters stand for the
parts of a pattern: `c` is the condition, `x` the value wanted when it holds,
and `y` the value wanted when it fails. Find the three in the last line and
write them beside their letters in the scratch pane.

`x` and `y` are values, where the checks so far were tests. What matters to
`and` and `or` is whether a value counts as true: in Lua everything does,
except `false` and `nil`. So `x` in the table to come means "`x` is neither
`false` nor `nil`".

There is no plugin command to run yet. `]]` reveals the key; `[[` brings you
back to your work.
]=],
            template = [[
c
x
y
]],
        },
        {
            text = [[
**Stages 2 and 3 of 5: translate, and compare.**

Compare your parts with this key:

```text
c    vim.islist(result)    the condition
x    result[1]             the value wanted when the condition holds
y    result                the value wanted when it fails
```

Two things to translate, the idiom and what it is meant to be:

```text
c and x or y                    the idiom, as written
if c then x else y              the intent
```

The idiom is already an expression. The intent is a ternary, and written out
with the connectives it is `(c ∧ x) ∨ (¬c ∧ y)`: `x` when `c` holds, `y`
when it does not.

Do the idiom and the intent have the same truthiness? There is nothing to
rewrite here; compare their Boolean expressions with a table. The scratch
pane holds both. Build the table (`:.TruthTable`, `<leader>ttn`). This checks
whether their results count as true, not whether they return the same value.
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
One Boolean row differs: `c` true, `x` false, `y` true. The condition holds,
and the idiom still falls through to `y`, because `c and x` came out false.

Lua's `and` and `or` return operand values, not necessarily Booleans. So
agreement in the other rows is not enough to prove value equality. With
`c = true`, `x = nil`, and `y = false`, both results count as false, but the
idiom returns `false` and the intended ternary returns `nil`. The table
cannot distinguish them.

To use the idiom as a value selector, check that whenever `c` holds, `x`
cannot be `false` or `nil`. If it can, the idiom selects `y` instead; that
only gives the intended value when `y` happens to equal `x`.
]],
            solution = {
                { on = "c and x or y | (c and x) or (not c and y)", run = { ".TruthTable" } },
            },
        },
        {
            text = [[
**Stage 4 of 5: back into Lua.**

The table points to a risk; the value example widens it. Look at every case
where the condition holds and `x` is `false` or `nil`, even if the truthiness
columns agree. Put the parts back in place of the letters:

```text
c true, x false or nil    vim.islist(result) holds,
                          and result[1] is false or nil
```

Can that happen? There are two premises to check. The empty-table guard
excludes an empty list, so a list reaching this line has a first item. That
rules out `nil`, but not `false`: `{false}` is a nonempty list, and the idiom
would return the list itself instead of its first item.

The second premise comes from the callback's input contract: a valid LSP
location list contains location objects, not Boolean values. Those objects
are tables, and tables count as true in Lua. With both premises, the idiom
selects the intended value. The guard alone is not the whole argument.

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

Source: [kickstart.nvim, lua/plugins/languages/zsh-utils.lua, line 48](https://github.com/cds-amal/kickstart.nvim/blob/2cbd7d2/lua/plugins/languages/zsh-utils.lua#L48)

Commuting the two is sound as logic, and would call a method on `nil`. The
laws are about truth values; which operand runs first is a second question,
and Lua answers it left to right.

There is nothing to run in this step.
]],
            template = [[
c    vim.islist(result)    the condition
x    result[1]             the value wanted when the condition holds
y    result                the value wanted when it fails

The Boolean row where the idiom and the ternary differ:

|  c  |  x  |  y  | (c ∧ x) ∨ y | (c ∧ x) ∨ (¬c ∧ y) |
|:---:|:---:|:---:|:-----------:|:------------------:|
|  1  |  0  |  1  |      1      |         0          |
]],
        },
        {
            text = [=[
**Stage 5 of 5: review** (your verdict).

The scratch pane holds the two versions. Before reading the review, write
your own verdict: keep the idiom or use the `if`? Give one benefit, one cost,
and the two premises that make the idiom safe in this callback.

Then consider a change in the input contract: the list may now contain
`false` as an item. Does the existing guard still make the idiom safe? State
what each
version would put in `loc` for `result = {false}`.

There is no plugin command to run. `]]` reveals the review; `[[` returns to
your verdict.
]=],
            template = [[
local loc = vim.islist(result) and result[1] or result

local loc = result
if vim.islist(result) then
  loc = result[1]
end
]],
        },
        {
            text = [[
**Stage 5 of 5: review** (compare your verdict).

This is the before and after: the scratch pane holds both. Consider the change
the way a code reviewer would.

What changed, by count:

```text
                                    before    after
lines                                    1        4
Boolean rows differing from intent       1        0
```

What the long form buys:

- **It selects the intended value**, even when `result[1]` is `false` or
  `nil`, for a list reaching this line.
- **It survives a change elsewhere.** The idiom relies on the empty-table
  guard and on lists containing location objects. Remove that guard and it
  starts returning the empty list where a location was expected, with
  nothing at this line to show for it.

What it costs:

- **Three more lines** for something the idiom says in one, in a form every
  Lua reader knows on sight.
- **A variable that is assigned twice**, where the idiom gives `loc` its
  value once.

The verdict: keep the idiom here. It is the common spelling, and the guard
plus the valid-location input contract rule out a falsey first item. If the
contract allowed `{false}`, the idiom would put that table in `loc`; the
`if` would put `false` there. In that case, use the `if`.

What the exercise changes is what a reviewer looks for: every
`c and x or y` comes with the question "when `c` holds, can `x` be `false`
or `nil`?" A line such as `enabled and false or default` fails that check
at a glance. A truth table exposes truthiness differences; checking the
returned values completes the argument.
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
