return {
    title = "Lua: guard clauses as one expression",
    aim = "Take a Lua function from code to an expression and back, in five stages, and review the result.",
    steps = {
        {
            text = [=[
## Working with Lua conditions

- **What carries across.** The logic laws apply across languages.
  Translating them back into code requires attention to the language's
  values and evaluation rules.
- **What we will work on.** Five Lua examples: four from a Neovim config,
  the kind of script that rarely gets a second look, and one from a
  textbook. Each excerpt links to its source.
- **How we will work.** Getting from code to an expression is a task of
  its own, and so is getting back. Every example uses the five stages below,
  and every step says which stage it belongs to.

### The five stages

1. **Name the checks.** Find the smallest tests the code makes and give
  each a letter.
2. **Translate.** Write the code as an expression in those letters.
3. **Rewrite or compare.** Apply the laws, one step per line, or compare
  expressions with a table. Use known input constraints when they matter.
4. **Back into Lua.** Put the tests back in place of the letters and write
  the code.
5. **Review.** Before and after, side by side: what the change buys and
  what it costs.

Press `]]` to begin the first example.
]=],
        },
        {
            text = [=[
**Stage 1 of 5: name the checks.**

This function decides whether a cursor position lies inside a range that a
language server reported:

```lua
local function range_contains_pos(range, line, char)
  if not range then
    return false
  end
  local start = range.start
  local stop = range['end']
  if line < start.line or line > stop.line then
    return false
  end
  if line == start.line and char < start.character then
    return false
  end
  if line == stop.line and char > stop.character then
    return false
  end
  return true
end
```

Source: [kickstart.nvim, lua/plugins/breadcrumbs.lua, lines 11 to 34](https://github.com/cds-amal/kickstart.nvim/blob/2cbd7d2/lua/plugins/breadcrumbs.lua#L11-L34)

The checks are the smallest tests the function makes, each of which is true
or false on its own. There are seven. Name them yourself in the scratch pane,
in order of appearance: `R` for the range is done, and `B`, `A`, `S`, `L`,
`E`, `G` wait for their test and what it means.

There is no plugin command to run yet. `]]` reveals the key; `[[` brings you
back to your work.
]=],
            template = [[
R    range                      there is a range
B
A
S
L
E
G
]],
        },
        {
            text = [[
**Stage 2 of 5: translate** (first of two steps).

Compare your names with this key:

```text
R    range                      there is a range
B    line < start.line          the line is before the start line
A    line > stop.line           the line is after the stop line
S    line == start.line         the cursor is on the start line
L    char < start.character     it is left of the start character
E    line == stop.line          the cursor is on the stop line
G    char > stop.character      it is right of the stop character
```

Now the guards, one at a time. The reading rule for a guard, in Lua:

- `if c then return false end` followed by the rest is `¬c ∧ rest`.

Start at the bottom of the function, where the rest is simplest:

```lua
if line == stop.line and char > stop.character then   -- E and G
  return false
end
return true
```

Here `c` is `E ∧ G`, and the rest is `return true`, which is `1`. So this tail
of the function is `¬(E ∧ G) ∧ 1`, the expression in the scratch pane; the
red part is about to go. Simplify (`<leader>ttz`) and apply it as a step
(`<leader>ttA`).
]],
            template = [[
not (E and G) [:red and 1]
]],
            expect = [[
not (E and G) and 1
≡ ¬(E ∧ G)             | by identity
]],
            note = [[
`∧ 1` changes nothing. A guard followed by `return true` contributes its
negated test and that is all: the tail says yes exactly when guard 4 has no
reason to say no.
]],
            solution = {
                { on = "not (E and G) and 1", run = { "TruthTableSimplify", "TruthTableApplyStep" } },
            },
        },
        {
            text = [[
**Stage 2 of 5: translate** (second of two steps).

Work upward from there. Each earlier guard puts its own `¬c ∧` in front of
everything below it, in green:

```logic
guard 4, then true   ¬(E ∧ G) ∧ 1
guard 3 in front     [:green ¬(S ∧ L) ∧] (¬(E ∧ G) ∧ 1)
guard 2 in front     [:green ¬(B ∨ A) ∧] (¬(S ∧ L) ∧ (¬(E ∧ G) ∧ 1))
guard 1 in front     [:green ¬¬R ∧] (¬(B ∨ A) ∧ (¬(S ∧ L) ∧ (¬(E ∧ G) ∧ 1)))
```

Guard 1 tests `not range`, so its `c` is `¬R`, and negating that gives `¬¬R`.
The last line is the whole function, exactly as the rule builds it, and it is
what the scratch pane holds. Tidy it: simplify twice (`<leader>ttz`), applying
each as a step (`<leader>ttA`).
]],
            template = [[
not not R and (not (B or A) and (not (S and L) and (not (E and G) and 1)))
]],
            expect = [[
not not R and (not (B or A) and (not (S and L) and (not (E and G) and 1)))
≡ R ∧ ¬(B ∨ A) ∧ ¬(S ∧ L) ∧ ¬(E ∧ G) ∧ 1                                      | by double negation
≡ R ∧ ¬(B ∨ A) ∧ ¬(S ∧ L) ∧ ¬(E ∧ G)                                          | by identity
]],
            note = [[
Two things happened in the first step. The double negation went, and so did
the nesting: a run of `∧` means the same however it is grouped, so the plugin
writes it flat.

What is left has one term per guard, each the guard's test negated. That is
the function as an expression: it says yes when none of its reasons for no
holds.
]],
            solution = {
                {
                    on = "not not R and (not (B or A) and (not (S and L) and (not (E and G) and 1)))",
                    run = { "TruthTableSimplify", "TruthTableApplyStep" },
                },
                {
                    on = "≡ R ∧ ¬(B ∨ A) ∧ ¬(S ∧ L) ∧ ¬(E ∧ G) ∧ 1                                      | by double negation",
                    at = "R",
                    run = { "TruthTableSimplify", "TruthTableApplyStep" },
                },
            },
        },
        {
            text = [[
**Stage 3 of 5: rewrite.**

The expression is correct and still phrased as reasons to say no. Turn them
into the conditions for yes: De Morgan (`<leader>ttd`) with the cursor on each
`¬(` in turn, the yellow ones, applying every preview as a step
(`<leader>ttA`).
]],
            template = [[
R ∧ [:yellow ¬(]B ∨ A) ∧ [:yellow ¬(]S ∧ L) ∧ [:yellow ¬(]E ∧ G)
]],
            expect = [[
R ∧ ¬(B ∨ A) ∧ ¬(S ∧ L) ∧ ¬(E ∧ G)
≡ R ∧ ¬B ∧ ¬A ∧ ¬(S ∧ L) ∧ ¬(E ∧ G)      | by De Morgan
≡ R ∧ ¬B ∧ ¬A ∧ (¬S ∨ ¬L) ∧ ¬(E ∧ G)     | by De Morgan
≡ R ∧ ¬B ∧ ¬A ∧ (¬S ∨ ¬L) ∧ (¬E ∨ ¬G)    | by De Morgan
]],
            note = [[
Every term now says what has to hold, and the expression is still in letters.
The next two steps take it back into Lua.
]],
            solution = {
                {
                    on = "R ∧ ¬(B ∨ A) ∧ ¬(S ∧ L) ∧ ¬(E ∧ G)",
                    at = "¬(B",
                    run = { "TruthTableDeMorgan", "TruthTableApplyStep" },
                },
                {
                    on = "≡ R ∧ ¬B ∧ ¬A ∧ ¬(S ∧ L) ∧ ¬(E ∧ G)    | by De Morgan",
                    at = "¬(S",
                    run = { "TruthTableDeMorgan", "TruthTableApplyStep" },
                },
                {
                    on = "≡ R ∧ ¬B ∧ ¬A ∧ (¬S ∨ ¬L) ∧ ¬(E ∧ G)    | by De Morgan",
                    at = "¬(E",
                    run = { "TruthTableDeMorgan", "TruthTableApplyStep" },
                },
            },
        },
        {
            text = [[
**Stage 4 of 5: back into Lua** (first of two steps).

The last line of the derivation is the answer in letters. Getting it back
into Lua is the first step of this example run in reverse, and it deserves the
same care. The scratch pane holds the line and the letters: try each move
there before reading it here.

First, put each test back in place of its letter:

```logic
R ∧ ¬(line < start.line) ∧ ¬(line > stop.line)
  ∧ (¬(line == start.line) ∨ ¬(char < start.character))
  ∧ (¬(line == stop.line) ∨ ¬(char > stop.character))
```

Then turn each negated comparison around. A comparison has an opposite that
says the same thing with no `¬`, red to green:

```logic
[:red ¬(x < y)]      [:green x >= y]
[:red ¬(x > y)]      [:green x <= y]
[:red ¬(x == y)]     [:green x ~= y]
```

(`~=` is how Lua writes "not equal".) That removes every negation:

```logic
R ∧ (line >= start.line) ∧ (line <= stop.line)
  ∧ ((line ~= start.line) ∨ (char >= start.character))
  ∧ ((line ~= stop.line) ∨ (char <= stop.character))
```

There is nothing to run in this step. The plugin works on the letters; what a
letter stands for is yours to carry in and back out.
]],
            template = [[
R ∧ ¬B ∧ ¬A ∧ (¬S ∨ ¬L) ∧ (¬E ∨ ¬G)

R    range                      there is a range
B    line < start.line          the line is before the start line
A    line > stop.line           the line is after the stop line
S    line == start.line         the cursor is on the start line
L    char < start.character     it is left of the start character
E    line == stop.line          the cursor is on the stop line
G    char > stop.character      it is right of the stop character
]],
        },
        {
            text = [[
**Stage 4 of 5: back into Lua** (second of two steps).

What is left is to write it as Lua. `∧` is `and`, `∨` is `or`, and the
comparisons need no parentheses of their own, since `and` and `or` bind looser
than they do:

```lua
return line >= start.line and line <= stop.line
  and (line ~= start.line or char >= start.character)
  and (line ~= stop.line or char <= stop.character)
```

So, what became of `R`? It stays a guard, ahead of everything else. As logic,
`R ∧ ...` would do. As code, `start` and `stop` are read out of `range`, and
that has to come after the check that there is a range. The laws are about
truth values, and say nothing of what must be evaluated first.

The function, after:

```lua
local function range_contains_pos(range, line, char)
  if not range then
    return false
  end
  local start = range.start
  local stop = range['end']
  return line >= start.line and line <= stop.line
    and (line ~= start.line or char >= start.character)
    and (line ~= stop.line or char <= stop.character)
end
```

The scratch pane holds the original, to compare. Its guards list the ways a
position can be outside the range. The new version states what being inside
means: between the two lines; on the start line, no further left than the
start; on the stop line, no further right than the stop.

`line ~= start.line or char >= start.character` is an implication in disguise.
It is `S → ¬L`, "if the cursor is on the start line, it is not left of the
start", which is how an implication usually turns up in code.

Is the new version better? The next step reviews it.
]],
            template = [[
```lua
local function range_contains_pos(range, line, char)
  if not range then
    return false
  end
  local start = range.start
  local stop = range['end']
  if line < start.line or line > stop.line then
    return false
  end
  if line == start.line and char < start.character then
    return false
  end
  if line == stop.line and char > stop.character then
    return false
  end
  return true
end
```
]],
        },
        {
            text = [[
**Stage 5 of 5: review.**

This is the before and after: the scratch pane holds both versions, one above
the other. Consider the change the way a code reviewer would, checking each
point below against the code.

What changed, by count:

```text
                        before    after
lines                       17       10
if statements                4        1
return statements            5        2
```

What the change buys:

- **It says what the function is for.** The original lists four ways to be
  outside the range and leaves "inside" as whatever is left over; a reader
  runs all four exits in their head to learn it. The new version states the
  definition.
- **The boundaries are on the page.** `>=` and `<=` show that both ends count
  as inside. Before, that had to be worked out from the strict `<` and `>` of
  the rejections, which is where an off-by-one hides.
- **The behaviour is the same, and there is an argument for it.** The
  derivation shows the two agree for every input. `and` stops at the first
  false operand, so the tests still run in the same order and stop at the same
  place.

What it costs:

- **The two `or` terms take a second look.** "On the start line and left of
  the start: no" is easier to read than
  `line ~= start.line or char >= start.character`.
- **The places to stop are gone.** Each guard was a line to put a breakpoint
  or a log message on. When the question is why a position was rejected, the
  guards answer it and the expression cannot.

What a reviewer would ask for is what this course keeps asking for: name the
parts.

```lua
local within_lines = line >= start.line and line <= stop.line
local not_before_start = line ~= start.line or char >= start.character
local not_after_stop = line ~= stop.line or char <= stop.character
return within_lines and not_before_start and not_after_stop
```

That answers the first cost and keeps what was gained. (All three tests now
run before they are combined, which is fine for plain comparisons and would
matter for a test that is slow or has an effect.)

The verdict: approve, with the names. Keep the guards where each rejection
needs its own log line or error; the two are the same function, and knowing
that is what lets you choose.
]],
            template = [[
Before:

```lua
local function range_contains_pos(range, line, char)
  if not range then
    return false
  end
  local start = range.start
  local stop = range['end']
  if line < start.line or line > stop.line then
    return false
  end
  if line == start.line and char < start.character then
    return false
  end
  if line == stop.line and char > stop.character then
    return false
  end
  return true
end
```

After:

```lua
local function range_contains_pos(range, line, char)
  if not range then
    return false
  end
  local start = range.start
  local stop = range['end']
  return line >= start.line and line <= stop.line
    and (line ~= start.line or char >= start.character)
    and (line ~= stop.line or char <= stop.character)
end
```
]],
        },
    },
}
