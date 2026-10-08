return {
    title = "Equivalence, tautology, contradiction",
    aim = "Use a table to test whether two expressions mean the same thing, and catch a refactor that does not.",
    steps = {
        {
            text = [[
Two expressions are *logically equivalent* when they have the same truth value
in every row: no state of the world can tell them apart. The table is the test.
Here is a claim to check: `a → b` says the same thing as `¬a ∨ b`. Build the
table from the line in the scratch pane (`:.TruthTable`, `<leader>ttn`).
]],
            template = [[
a implies b | not a or b
]],
            expect = [[
|  a  |  b  | a → b | ¬a ∨ b |
|:---:|:---:|:-----:|:------:|
|  0  |  0  |   1   |   1    |
|  0  |  1  |   1   |   1    |
|  1  |  0  |   0   |   0    |
|  1  |  1  |   1   |   1    |
]],
            note = [[
The two computed columns match row for row, so the claim holds. Equivalence is
written `≡`: `a → b ≡ ¬a ∨ b`.
]],
            solution = {
                { on = "a implies b | not a or b", run = { ".TruthTable" } },
            },
        },
        {
            text = [[
There is a second way to see it. `⇔` is true when its two sides agree, so the
`⇔` of two equivalent expressions is true in every row. An expression that is
true in every row is a *tautology*.

With the cursor in the table, add that column. `:h3` and `:h4` refer to the
third and fourth columns by position, which saves retyping them:

    :TruthTableExpand :h3 iff :h4
]],
            template = [[
|  a  |  b  | a → b | ¬a ∨ b |
|:---:|:---:|:-----:|:------:|
|  0  |  0  |   1   |   1    |
|  0  |  1  |   1   |   1    |
|  1  |  0  |   0   |   0    |
|  1  |  1  |   1   |   1    |
]],
            expect = [[
|  a  |  b  | a → b | ¬a ∨ b | “a → b” ⇔ “¬a ∨ b” |
|:---:|:---:|:-----:|:------:|:------------------:|
|  0  |  0  |   1   |   1    |         1          |
|  0  |  1  |   1   |   1    |         1          |
|  1  |  0  |   0   |   0    |         1          |
|  1  |  1  |   1   |   1    |         1          |
]],
            note = [[
All ones: the two expressions agree in every state of the world.
]],
            solution = {
                { on = "|  a  |  b  | a → b | ¬a ∨ b |", run = { "TruthTableExpand :h3 iff :h4" } },
            },
        },
        {
            text = [[
The opposite of a tautology is a *contradiction*, an expression that is false
in every row. The simplest one says a thing is both true and not true. With the
cursor in the table:

    :TruthTableExpand a and not a
]],
            template = [[
|  a  |  b  | a → b | ¬a ∨ b | “a → b” ⇔ “¬a ∨ b” |
|:---:|:---:|:-----:|:------:|:------------------:|
|  0  |  0  |   1   |   1    |         1          |
|  0  |  1  |   1   |   1    |         1          |
|  1  |  0  |   0   |   0    |         1          |
|  1  |  1  |   1   |   1    |         1          |
]],
            expect = [[
|  a  |  b  | a → b | ¬a ∨ b | “a → b” ⇔ “¬a ∨ b” | a ∧ ¬a |
|:---:|:---:|:-----:|:------:|:------------------:|:------:|
|  0  |  0  |   1   |   1    |         1          |   0    |
|  0  |  1  |   1   |   1    |         1          |   0    |
|  1  |  0  |   0   |   0    |         1          |   0    |
|  1  |  1  |   1   |   1    |         1          |   0    |
]],
            note = [[
All zeros, whatever `a` and `b` are.
]],
            solution = {
                {
                    on = "|  a  |  b  | a → b | ¬a ∨ b | “a → b” ⇔ “¬a ∨ b” |",
                    run = { "TruthTableExpand a and not a" },
                },
            },
        },
        {
            text = [[
Equivalence is the question every refactor of a condition asks: does the new
version mean the same as the old one? Here is a function with two ways to say
yes:

```js
function canEdit({ isPrivileged, hasGrant, isSuspended }) {
  if (isPrivileged) return true;
  if (hasGrant && !isSuspended) return true;
  return false;
}
```

A function that only ever returns true or false is a logic expression written
as control flow: each branch that returns true is a term, and the terms are
joined by `or`. With `P`, `G`, `S` for the three checks, this one is
`P ∨ (G ∧ ¬S)`.

Two branches that both return true look as if they could be merged, and a
reviewer proposes `return (isPrivileged || hasGrant) && !isSuspended;`, which
is `(P ∨ G) ∧ ¬S`. Is it the same function? The scratch pane holds both
expressions. Build the table (`:.TruthTable`, `<leader>ttn`).
]],
            template = [[
P or (G and not S) | (P or G) and not S
]],
            expect = [[
|  P  |  G  |  S  | P ∨ (G ∧ ¬S) | (P ∨ G) ∧ ¬S |
|:---:|:---:|:---:|:------------:|:------------:|
|  0  |  0  |  0  |      0       |      0       |
|  0  |  0  |  1  |      0       |      0       |
|  0  |  1  |  0  |      1       |      1       |
|  0  |  1  |  1  |      0       |      0       |
|  1  |  0  |  0  |      1       |      1       |
|  1  |  0  |  1  |      1       |      0       |
|  1  |  1  |  0  |      1       |      1       |
|  1  |  1  |  1  |      1       |      0       |
]],
            note = [[
The columns differ in two rows, `1 0 1` and `1 1 1`: a privileged user who is
suspended. The original lets them edit, and the merged version locks them out.
The suspension check governs the grant alone in the first, in blue, and both
branches in the second, in red:

```logic
P ∨ (G ∧ [:blue ¬S])
(P ∨ G) ∧ [:red ¬S]
```
(`:TruthTableExpand :h4 iff :h5` would mark those rows with a `0`: the claim
is no tautology.)

A test suite catches this only if someone thought to write that case. The
table has every case by construction, which is the reason to build one before
trusting a refactor: if you cannot enumerate the cases, you are guessing.
]],
            solution = {
                { on = "P or (G and not S) | (P or G) and not S", run = { ".TruthTable" } },
            },
        },
    },
}
