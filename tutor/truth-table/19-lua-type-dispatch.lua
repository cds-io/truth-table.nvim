return {
    title = "Lua: a dispatch on type, simplified with domain knowledge",
    aim = "Use mutually exclusive types to simplify branch conditions, then choose and justify a structure for the code.",
    steps = {
        {
            text = [[
**Stage 1 of 5: name the checks.**

The last example is a textbook one: a function that writes a value out as Lua
code, tables included, and copes with tables that refer to each other.

```lua
function save (name, value, saved)
  saved = saved or {}       -- initial value
  io.write(name, " = ")
  if type(value) == "number" or type(value) == "string" then
    io.write(basicSerialize(value), "\n")
  elseif type(value) == "table" then
    if saved[value] then    -- value already saved?
      io.write(saved[value], "\n")  -- use its previous name
    else
      saved[value] = name   -- save name for next time
      io.write("{}\n")     -- create a new table
      for k,v in pairs(value) do      -- save its fields
        local fieldname = string.format("%s[%s]", name,
                                        basicSerialize(k))
        save(fieldname, v, saved)
      end
    end
  else
    error("cannot save a " .. type(value))
  end
end
```

Source: Roberto Ierusalimschy, *Programming in Lua* (first edition), section 12.1.2, "Saving Tables with Cycles": https://www.lua.org/pil/12.1.2.html

It returns nothing, so there is no true or false to read off. The branches are
still there, and each one runs under a condition, which is all the method
needs. The function makes four tests:

```text
N    type(value) == "number"    the value is a number
S    type(value) == "string"    the value is a string
T    type(value) == "table"     the value is a table
V    saved[value]               this table has been saved already
```

There is nothing to run in this step.
]],
        },
        {
            text = [[
**Stage 2 of 5: translate.**

The rule for branches, from the lesson on `elseif`: a branch runs when its own
test holds and every test before it failed. An `if` nested inside a branch
adds its test with `∧`. Use those rules and the code from the previous step
to write the conditions for all four actions in your scratch pane: write a
scalar, reuse a table's name, create a new table, and raise the error.

Then find the condition shared by the two table actions: what must hold to
reach the inner `if` at all? Give that expression to `:TruthTable` and compare
your table with the one below. The naming key is in the previous step; this
time you supply the branch expressions.
]],
            expect = [[
|  N  |  S  |  T  | ¬(N ∨ S) ∧ T |
|:---:|:---:|:---:|:------------:|
|  0  |  0  |  0  |      0       |
|  0  |  0  |  1  |      1       |
|  0  |  1  |  0  |      0       |
|  0  |  1  |  1  |      0       |
|  1  |  0  |  0  |      0       |
|  1  |  0  |  1  |      0       |
|  1  |  1  |  0  |      0       |
|  1  |  1  |  1  |      0       |
]],
            note = [[
One row in eight. Look at the rows before reaching for a law, though: some of
them describe a value that is a number and a table at once.

Compare the four conditions you wrote with this key; the condition the two
table actions share is in blue:

```logic
write the value itself           N ∨ S
write the table's earlier name   [:blue ¬(N ∨ S) ∧ T] ∧ V
write a new table and recurse    [:blue ¬(N ∨ S) ∧ T] ∧ ¬V
raise the error                  ¬(N ∨ S) ∧ ¬T
```
]],
            solution = {
                { run = { "TruthTable not (N or S) and T" } },
            },
        },
        {
            text = [[
**Stage 3 of 5: rewrite.**

A value has exactly one type, so no two of `N`, `S` and `T` are ever true
together. This is domain knowledge supplied by Lua's type system, not a fact
the Boolean table can discover. Identify the four rows that violate it and
remove them, with the cursor on each in turn (`:TruthTableDropRow`,
`<leader>ttr`). Then put the cursor in the last column and ask for the
Karnaugh map (`:TruthTableKarnaugh`, `<leader>ttk`). Keep `0 0 0`: the value
can have a type other than number, string or table.
]],
            template = [[
|  N  |  S  |  T  | ¬(N ∨ S) ∧ T |
|:---:|:---:|:---:|:------------:|
|  0  |  0  |  0  |      0       |
|  0  |  0  |  1  |      1       |
|  0  |  1  |  0  |      0       |
|  0  |  1  |  1  |      0       |
|  1  |  0  |  0  |      0       |
|  1  |  0  |  1  |      0       |
|  1  |  1  |  0  |      0       |
|  1  |  1  |  1  |      0       |
]],
            expect = [[
|  N  |  S  |  T  | ¬(N ∨ S) ∧ T |
|:---:|:---:|:---:|:------------:|
|  0  |  0  |  0  |      0       |
|  0  |  0  |  1  |      1       |
|  0  |  1  |  0  |      0       |
|  1  |  0  |  0  |      0       |

Karnaugh map for ¬(N ∨ S) ∧ T:

|     |     |     | ST  |     |     |
|:---:|:---:|:---:|:---:|:---:|:---:|
|     |     | 00  | 01  | 11  | 10  |
|  N  |  0  |  0  |  1  |  X  |  0  |
|     |  1  |  0  |  X  |  X  |  X  |

¬(N ∨ S) ∧ T ≡ T
]],
            note = [[
`T`, and nothing else. The four missing rows are don't-cares (the `X` cells),
and with them in play the `¬(N ∨ S)` that the `elseif` contributed falls away:
a table is never a number or a string, so saying so adds nothing.

This is a simplification using domain knowledge: `¬(N ∨ S) ∧ T` becomes
`T` on the inputs Lua can actually supply. They differ on some of the dropped
rows, so this is not an unrestricted Boolean identity.

The table actions now have conditions `T ∧ V` and `T ∧ ¬V`. The scalar
action remains `N ∨ S`, and the error condition is `¬N ∧ ¬S ∧ ¬T`.
The type cases cannot overlap. Because these type checks are also safe and
have no effects, we can change their order without changing which action
runs. Keep the `saved[value]` check inside the table case.
]],
            solution = {
                { on = "|  0  |  1  |  1  |      0       |", run = { "TruthTableDropRow" } },
                { on = "|  1  |  0  |  1  |      0       |", run = { "TruthTableDropRow" } },
                { on = "|  1  |  1  |  0  |      0       |", run = { "TruthTableDropRow" } },
                { on = "|  1  |  1  |  1  |      0       |", run = { "TruthTableDropRow" } },
                { on = "|  N  |  S  |  T  | ¬(N ∨ S) ∧ T |", at = "¬(N", run = { "TruthTableKarnaugh" } },
            },
        },
        {
            text = [=[
**Stage 4 of 5: back into Lua** (your turn).

Use the simplified conditions in the scratch pane to write your own version
of `save`. Go back to the first step for the original code. Keep its writes,
saved-name bookkeeping, and recursive calls in the same order for each case.

Try a guard structure: finish the scalar case early, reject unsupported
types before accessing `saved[value]`, then finish the already-saved table
case early. Leave creation of a new table at the top level. Give the type a
local name so you ask for it once.

Before moving on, review your version. Which conditions became simpler
because of the type constraint? Which check still needs a guard before it?
Would you keep the original or take your rewrite, and why?

There is no plugin command to run. `]]` reveals one possible implementation,
then its review. Your scratch work stays here for comparison.
]=],
            template = [[
write the value itself           N ∨ S
write the table's earlier name   T ∧ V
write a new table and recurse    T ∧ ¬V
raise the error                  ¬N ∧ ¬S ∧ ¬T

N    type(value) == "number"
S    type(value) == "string"
T    type(value) == "table"
V    saved[value]
]],
        },
        {
            text = [[
**Stage 4 of 5: back into Lua** (compare your version).

The table conditions lost their redundant exclusions of number and string.
Now translate those simplified conditions back, preserving the safety of
each check and the sequence of actions within each case.

Put the tests back in place of the letters, branch by branch (the scratch
pane holds the list). `type(value)` appears in every one, so give it a name
first:

```lua
local kind = type(value)
```

Then take the branches as guards, each one leaving the function when it is
done, the short cases first:

```lua
function save(name, value, saved)
  saved = saved or {}
  io.write(name, " = ")
  local kind = type(value)
  if kind == "number" or kind == "string" then
    io.write(basicSerialize(value), "\n")
    return
  end
  if kind ~= "table" then
    error("cannot save a " .. kind)
  end
  if saved[value] then
    io.write(saved[value], "\n")   -- already saved: use its name
    return
  end
  saved[value] = name
  io.write("{}\n")
  for k, v in pairs(value) do
    save(string.format("%s[%s]", name, basicSerialize(k)), v, saved)
  end
end
```

The error has moved up beside the other type tests; in the original it trails
the whole table branch. There is nothing to run in this step.
]],
            template = [[
N    type(value) == "number"    the value is a number
S    type(value) == "string"    the value is a string
T    type(value) == "table"     the value is a table
V    saved[value]               this table has been saved already

write the value itself           N ∨ S
write the table's earlier name   T ∧ V
write a new table and recurse    T ∧ ¬V
raise the error                  ¬N ∧ ¬S ∧ ¬T
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
lines                                  21       21
deepest nesting                         4        2
calls to `type` for a table             3        1
ways out of the function                1        3
```

What the change buys:

- **The main work is at the top level.** Saving a new table is what the
  function is for, and in the original it sits four levels deep, inside an
  `else` inside an `elseif`. Now it is the last thing in the function, with
  nothing around it.
- **The type tests sit together.** Number or string, then "anything that is
  no table", then the table's two cases. A new type is one more guard.
- **`type(value)` is asked once**, and the answer has a name.
- **The behaviour is the same.** Both versions write the same text for
  numbers, strings, nested tables, shared tables and tables that contain
  themselves, and raise the same error for a value they cannot save.

What it costs:

- **Three ways out, where there was one.** The original is a single `if`
  chain with every case visible as a branch of it. The guards have to be read
  in order.
- **No fewer lines.** The gain is in depth, and the count stays at 21.

The verdict: a matter of taste at this size, and the original has a good
claim to stay. It was written to be read beside an explanation, and its shape
follows the cases one by one. Take the flat form when the dispatch grows.

What did the logic contribute? It made the path conditions explicit, then
simplified them under a known type constraint. Removing four rows encoded
that constraint; it did not establish it. The resulting table checks the
simplification on every remaining case.

The restructuring also relies on facts about the code: the type checks are
safe and have no effects, `saved[value]` is reached only for tables, and each
case keeps its sequence of writes and updates. Compare your own review with
those requirements. A smaller expression is part of the argument for a
refactor, and the evaluation and actions complete it.

That is the last of the Lua examples. The five stages are the same in any
language: name the checks, translate, rewrite, translate back, and look at
what you have with a reviewer's eye.
]],
            template = [[
Before:

```lua
function save (name, value, saved)
  saved = saved or {}       -- initial value
  io.write(name, " = ")
  if type(value) == "number" or type(value) == "string" then
    io.write(basicSerialize(value), "\n")
  elseif type(value) == "table" then
    if saved[value] then    -- value already saved?
      io.write(saved[value], "\n")  -- use its previous name
    else
      saved[value] = name   -- save name for next time
      io.write("{}\n")     -- create a new table
      for k,v in pairs(value) do      -- save its fields
        local fieldname = string.format("%s[%s]", name,
                                        basicSerialize(k))
        save(fieldname, v, saved)
      end
    end
  else
    error("cannot save a " .. type(value))
  end
end
```

After:

```lua
function save(name, value, saved)
  saved = saved or {}
  io.write(name, " = ")
  local kind = type(value)
  if kind == "number" or kind == "string" then
    io.write(basicSerialize(value), "\n")
    return
  end
  if kind ~= "table" then
    error("cannot save a " .. kind)
  end
  if saved[value] then
    io.write(saved[value], "\n")   -- already saved: use its name
    return
  end
  saved[value] = name
  io.write("{}\n")
  for k, v in pairs(value) do
    save(string.format("%s[%s]", name, basicSerialize(k)), v, saved)
  end
end
```
]],
        },
    },
}
