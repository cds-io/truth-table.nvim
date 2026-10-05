return {
    title = "Lua: the condition behind an `elseif`",
    aim = "Work out the condition a later branch of an `if` runs under, and decide what to do with it.",
    steps = {
        {
            text = [=[
**Stage 1 of 5: name the checks.**

This loop, from the same plugin as the last lesson, walks along a line of
text. At each stop it looks for the next string and the next line comment, and
acts on whichever starts first:

```lua
local quote = line:find('"', i, true)
local comment = line:find([[\*]], i, true)
if comment and (not quote or comment < quote) then
  -- the rest of the line is a comment: leave it as it is
elseif quote then
  -- a string starts here: skip to its closing quote
else
  -- neither: convert the rest of the line
end
```

Source: https://github.com/cds-amal/kickstart.nvim/blob/2cbd7d2f997a430fc6156eb97865f630961a2f6b/ftplugin/tla.lua#L160-L190

`line:find` gives a position, or `nil` when there is nothing to find. The two
tests of the `if` are built from three checks:

```text
C    comment            there is a line comment ahead
Q    quote              there is a quote ahead
L    comment < quote    the comment starts before the quote
```

There is nothing to run in this step. The question for the lesson: under what
condition, exactly, does the middle branch run?
]=],
        },
        {
            text = [[
**Stage 2 of 5: translate.**

An `if` with an `elseif` hides a condition. A later branch runs when its own
test holds and every test before it failed:

- In `if a then X elseif b then Y else Z end`, `X` runs when `a`, `Y` runs
  when `¬a ∧ b`, and `Z` runs when `¬a ∧ ¬b`.

Here `a` is the first test and `b` is `quote`:

```text
if comment and (not quote or comment < quote)      a  is  C and (not Q or L)
elseif quote                                       b  is  Q
```

So the middle branch runs under `¬a ∧ b`. Write that out in the letters, give
it to `:TruthTable` (the scratch pane is empty), and compare your table with
the one below.
]],
            expect = [[
|  C  |  Q  |  L  | ¬(C ∧ (¬Q ∨ L)) ∧ Q |
|:---:|:---:|:---:|:-------------------:|
|  0  |  0  |  0  |          0          |
|  0  |  0  |  1  |          0          |
|  0  |  1  |  0  |          1          |
|  0  |  1  |  1  |          1          |
|  1  |  0  |  0  |          0          |
|  1  |  0  |  1  |          0          |
|  1  |  1  |  0  |          1          |
|  1  |  1  |  1  |          0          |
]],
            note = [[
The table is the meaning of the middle branch, case by case. The expression
that produced it is correct and says little: "not (a comment and (no quote or
comment first)), and a quote". The next two steps turn it into something a
person would say.
]],
            solution = {
                { run = { "TruthTable not (C and (not Q or L)) and Q" } },
            },
        },
        {
            text = [[
**Stage 3 of 5: rewrite** (first of two steps).

Start by pushing the negation in. De Morgan (`<leader>ttd`) on the leading
`not`; De Morgan again on the `¬(` that appears; then simplify
(`<leader>ttz`) for the double negation. Apply each as a step
(`<leader>ttA`).
]],
            template = [[
not (C and (not Q or L)) and Q
]],
            expect = [[
not (C and (not Q or L)) and Q
≡ (¬C ∨ ¬(¬Q ∨ L)) ∧ Q            | by De Morgan
≡ (¬C ∨ (¬¬Q ∧ ¬L)) ∧ Q           | by De Morgan
≡ (¬C ∨ (Q ∧ ¬L)) ∧ Q             | by double negation
]],
            note = [[
The negations now sit on single letters, and `Q` appears twice. The next step
deals with that.
]],
            solution = {
                { on = "not (C and (not Q or L)) and Q", at = "not", run = { "TruthTableDeMorgan", "TruthTableApplyStep" } },
                {
                    on = "≡ (¬C ∨ ¬(¬Q ∨ L)) ∧ Q            | by De Morgan",
                    at = "¬(¬Q",
                    run = { "TruthTableDeMorgan", "TruthTableApplyStep" },
                },
                {
                    on = "≡ (¬C ∨ (¬¬Q ∧ ¬L)) ∧ Q           | by De Morgan",
                    at = "¬¬Q",
                    run = { "TruthTableSimplify", "TruthTableApplyStep" },
                },
            },
        },
        {
            text = [[
**Stage 3 of 5: rewrite** (second of two steps).

The scratch pane starts from where the last step ended. Four more moves, each
applied as a step (`<leader>ttA`):

- Bring the outer `Q` to the front: cursor on the last `Q`, commute
  (`<leader>tts`).
- Distribute it into the group (`<leader>ttx`; the cursor is already on it).
- Simplify (`<leader>ttz`), which finds the `Q` that is now said twice.
- Factor `Q` back out: cursor on a `Q`, `<leader>ttf`.
]],
            template = [[
(¬C ∨ (Q ∧ ¬L)) ∧ Q
]],
            expect = [[
(¬C ∨ (Q ∧ ¬L)) ∧ Q
≡ Q ∧ (¬C ∨ (Q ∧ ¬L))    | by commutativity
≡ (Q ∧ ¬C) ∨ (Q ∧ Q ∧ ¬L)    | by distributivity (distributing)
≡ (Q ∧ ¬C) ∨ (Q ∧ ¬L)        | by idempotence
≡ Q ∧ (¬C ∨ ¬L)              | by distributivity (factoring)
]],
            note = [[
`Q ∧ (¬C ∨ ¬L)`: a quote, and no comment before it. That is what the `elseif`
means.

To check all seven steps at once, put the first line and the last side by
side:

    :TruthTable not (C and (not Q or L)) and Q | Q and (not C or not L)
]],
            solution = {
                { on = "(¬C ∨ (Q ∧ ¬L)) ∧ Q", at = ") ∧ Q", run = { "TruthTableCommute", "TruthTableApplyStep" } },
                {
                    on = "≡ Q ∧ (¬C ∨ (Q ∧ ¬L))    | by commutativity",
                    at = "Q",
                    run = { "TruthTableDistribute", "TruthTableApplyStep" },
                },
                {
                    on = "≡ (Q ∧ ¬C) ∨ (Q ∧ Q ∧ ¬L)    | by distributivity (distributing)",
                    at = "(Q",
                    run = { "TruthTableSimplify", "TruthTableApplyStep" },
                },
                {
                    on = "≡ (Q ∧ ¬C) ∨ (Q ∧ ¬L)        | by idempotence",
                    at = "Q",
                    run = { "TruthTableFactor", "TruthTableApplyStep" },
                },
            },
        },
        {
            text = [[
**Stage 4 of 5: back into Lua.**

Put the tests back in place of the letters, then turn the negated comparison
around (`¬(x < y)` is `x >= y`):

```text
Q ∧ (¬C ∨ ¬L)
quote ∧ (¬comment ∨ ¬(comment < quote))
quote ∧ (¬comment ∨ comment >= quote)
```

In Lua, with a name for what it says:

```lua
local string_first = quote and (not comment or comment >= quote)
```

Set that beside the first test, and the two turn out to be mirror images:

```lua
local comment_first = comment and (not quote or comment < quote)
local string_first = quote and (not comment or comment >= quote)
```

The same reading rule gives the last branch, `¬a ∧ ¬b`, which comes to
`¬C ∧ ¬Q`: neither. So the three branches are "comment first", "string first"
and "neither". Do they cover every case, with no overlap? The scratch pane
holds the three conditions. Build the table (`:.TruthTable`, `<leader>ttn`).
]],
            template = [[
C and (not Q or L) | Q and (not C or not L) | not C and not Q
]],
            expect = [[
|  C  |  Q  |  L  | C ∧ (¬Q ∨ L) | Q ∧ (¬C ∨ ¬L) | ¬C ∧ ¬Q |
|:---:|:---:|:---:|:------------:|:-------------:|:-------:|
|  0  |  0  |  0  |      0       |       0       |    1    |
|  0  |  0  |  1  |      0       |       0       |    1    |
|  0  |  1  |  0  |      0       |       1       |    0    |
|  0  |  1  |  1  |      0       |       1       |    0    |
|  1  |  0  |  0  |      1       |       0       |    0    |
|  1  |  0  |  1  |      1       |       0       |    0    |
|  1  |  1  |  0  |      0       |       1       |    0    |
|  1  |  1  |  1  |      1       |       0       |    0    |
]],
            note = [[
Every row has exactly one `1`. Whatever the line holds, one branch runs and
only one, and now each branch has a condition you can say out loud.
]],
            solution = {
                { on = "C and (not Q or L) | Q and (not C or not L) | not C and not Q", run = { ".TruthTable" } },
            },
        },
        {
            text = [[
**Stage 5 of 5: review.**

This is the before and after: the scratch pane holds both. This time the
"after" spells every branch out, and the review has to decide whether that is
an improvement.

What changed, by count:

```text
                             before    after
lines                             7        9
conditions with a name            0        2
comparisons of the positions      1        2
```

What the long form buys:

- **Each branch says when it runs.** In the original, the middle branch
  tests `quote` and depends on the first test having failed. The reader
  supplies the rest.
- **The symmetry shows.** `comment_first` and `string_first` are the same
  shape with the roles swapped, which the original hides.

What it costs:

- **It asks twice.** By the time the `elseif` is reached, the first test has
  already failed. `string_first` tests again what the `if` just settled; the
  short `elseif quote` was correct, and was the cheaper way to say it.
- **Two more lines**, and two conditions to keep in step if one changes.

The verdict: take the names and leave the long form. Name the first test, keep
`elseif quote`, and let a comment carry what the derivation found:

```lua
local comment_first = comment and (not quote or comment < quote)
if comment_first then
  -- the rest of the line is a comment: leave it as it is
elseif quote then -- a string, and no comment before it
  -- skip to its closing quote
else -- neither
  -- convert the rest of the line
end
```

A derivation does not have to end in a rewrite. Here it ends in a comment that
is known to be true, and a table showing that the three branches cover every
case once.
]],
            template = [[
Before:

```lua
if comment and (not quote or comment < quote) then
  -- the rest of the line is a comment: leave it as it is
elseif quote then
  -- a string starts here: skip to its closing quote
else
  -- neither: convert the rest of the line
end
```

After, with every branch spelled out:

```lua
local comment_first = comment and (not quote or comment < quote)
local string_first = quote and (not comment or comment >= quote)
if comment_first then
  -- the rest of the line is a comment: leave it as it is
elseif string_first then
  -- a string starts here: skip to its closing quote
else
  -- neither: convert the rest of the line
end
```
]],
        },
    },
}
