return {
    title = "Lua: two negations, one name",
    aim = "Pull two negated conditions into one with De Morgan, and give the result a name.",
    steps = {
        {
            text = [=[
**Stage 1 of 5: name the checks.**

This condition comes from a filetype plugin that converts ASCII operators to
Unicode as you type. Each conversion rule is tried at a position, unless
something about the previous character rules it out:

```lua
local prev = i > 1 and s:sub(i - 1, i - 1) or ''
for _, rule in ipairs(bucket) do
  if not (rule.needs_word_start and prev:match '[%w_]') and not (rule.not_after == prev) then
    -- try the rule at this position
  end
end
```

Source: https://github.com/cds-amal/kickstart.nvim/blob/2cbd7d2f997a430fc6156eb97865f630961a2f6b/ftplugin/tla.lua#L125-L127

The `if` makes three tests. This time, name them yourself in the scratch
pane: use `N`, `W` and `A`, in order of appearance, and write what each means.
Then write the condition in those letters. Keep the parentheses and the
negations where the code puts them.

There is no plugin command to run yet. `]]` reveals the naming key and lets
you check your translation with a table; `[[` brings you back to your work.
]=],
        },
        {
            text = [[
**Stage 2 of 5: translate.**

Compare your names with this key:

```text
N    rule.needs_word_start     the rule applies only at the start of a word
W    prev:match '[%w_]'        the previous character is a word character
A    rule.not_after == prev    the previous character is the one this rule
                               must not follow
```

The scratch pane is empty. Give the expression you wrote in the previous
step to `:TruthTable` and compare the table with the one below.
]],
            expect = [[
|  N  |  W  |  A  | ¬(N ∧ W) ∧ ¬A |
|:---:|:---:|:---:|:-------------:|
|  0  |  0  |  0  |       1       |
|  0  |  0  |  1  |       0       |
|  0  |  1  |  0  |       1       |
|  0  |  1  |  1  |       0       |
|  1  |  0  |  0  |       1       |
|  1  |  0  |  1  |       0       |
|  1  |  1  |  0  |       0       |
|  1  |  1  |  1  |       0       |
]],
            note = [[
The rule is tried in three rows of the eight. A table that differs from this
one means a letter or a parenthesis went astray in the translation, and the
rows that differ say which.

The parentheses around `A` are gone from the heading: the plugin writes only
the ones an expression needs.
]],
            solution = {
                { run = { "TruthTable not (N and W) and not A" } },
            },
        },
        {
            text = [[
**Stage 3 of 5: rewrite.**

The condition denies two things, and a reader has to hold both to see when
the rule is tried. De Morgan can pull the two negations into one.

Which De Morgan, though? The command takes the nearest match around the
cursor. On the first `not`, that is the group behind it, and the negation
would be pushed inward. Put the cursor on the `and` between the two negated
groups, so that the match is the pair. Preview (`<leader>ttd`) and apply it as
a step (`<leader>ttA`).
]],
            template = [[
not (N and W) and not A
]],
            expect = [[
not (N and W) and not A
≡ ¬((N ∧ W) ∨ A)           | by De Morgan
]],
            note = [[
One negation, of one thing. Inside it is a plain list of the ways a rule can
be ruled out: it needs a word start and is not at one, or it follows the
character it must not follow.
]],
            solution = {
                { on = "not (N and W) and not A", at = "and not A", run = { "TruthTableDeMorgan", "TruthTableApplyStep" } },
            },
        },
        {
            text = [[
**Stage 4 of 5: back into Lua.**

The scratch pane holds the derived line and the letters. Put each test back
in place of its letter:

```text
¬((rule.needs_word_start ∧ prev:match '[%w_]') ∨ rule.not_after == prev)
```

There are no negated comparisons to turn around this time: the `not` that sat
on `rule.not_after == prev` went into the single negation in front.

The thing being negated is now one expression, so it can have a name. It is
true when the previous character rules the rule out; call it `blocked`. With
`∧` as `and`, `∨` as `or` and `¬` as `not`:

```lua
local blocked = (rule.needs_word_start and prev:match '[%w_]') or rule.not_after == prev
if not blocked then
  -- try the rule at this position
end
```

There is nothing to run in this step.
]],
            template = [[
¬((N ∧ W) ∨ A)

N    rule.needs_word_start     the rule applies only at the start of a word
W    prev:match '[%w_]'        the previous character is a word character
A    rule.not_after == prev    the previous character is the one this rule
                               must not follow
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
lines                        1        2
negations                    2        1
longest line                91       88
```

What the change buys:

- **One idea in place of two.** The original says "not this, and not that",
  and the reader combines them. The new version says "not blocked", and
  `blocked` lists what blocks.
- **The list reads positively.** Inside `blocked` there is no negation at
  all: a rule is blocked when it needs a word start and has a word character
  before it, or when it follows the character it must not follow.
- **It has room to grow.** A third way to block a rule is one more `or`
  term. In the original it would be a third `and not (...)`.
- **Nothing else moved.** `prev:match` and the comparison run in the same
  order as before, and the comparison is still skipped when the first group
  already settles the answer.

What it costs:

- **A line and a local.** Small, and the local is what carries the name.
- **`blocked` is not always `true` or `false`.** `prev:match` returns the
  matched text, so `blocked` can hold a string. Under `not` that makes no
  difference; it would if the value were stored or compared with `== true`.

The verdict: approve. The derivation is one line, and it is the whole
argument that the two conditions agree.
]],
            template = [[
Before:

```lua
if not (rule.needs_word_start and prev:match '[%w_]') and not (rule.not_after == prev) then
  -- try the rule at this position
end
```

After:

```lua
local blocked = (rule.needs_word_start and prev:match '[%w_]') or rule.not_after == prev
if not blocked then
  -- try the rule at this position
end
```
]],
        },
    },
}
