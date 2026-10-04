return {
    title = "Absorption and reduction",
    aim = "Shrink an expression with the absorption and reduction laws, by derivation and in one move.",
    steps = {
        {
            text = [[
The laws so far reshape an expression. The next two families shrink one, which
is what simplifying a condition comes down to.

*Absorption*: beside `a` itself, a term that already contains `a` adds nothing.

```text
a ∨ (a ∧ b)  ≡  a
a ∧ (a ∨ b)  ≡  a
```

In words, for the first: `a ∧ b` can only be true when `a` is, so `or`-ing it
onto `a` changes no row. Build the table from the line in the scratch pane
(`:.TruthTable`, `<leader>ttn`) and compare both computed columns with the `a`
column.
]],
            template = [[
a or (a and b) | a and (a or b)
]],
            expect = [[
|  a  |  b  | a ∨ (a ∧ b) | a ∧ (a ∨ b) |
|:---:|:---:|:-----------:|:-----------:|
|  0  |  0  |      0      |      0      |
|  0  |  1  |      0      |      0      |
|  1  |  0  |      1      |      1      |
|  1  |  1  |      1      |      1      |
]],
            note = [[
Both columns repeat `a`: `b` has been absorbed. In code,
`ready || (ready && verbose)` is `ready`.
]],
            solution = {
                { on = "a or (a and b) | a and (a or b)", run = { ".TruthTable" } },
            },
        },
        {
            text = [[
A second form of absorption drops a negation:

```text
a ∨ (¬a ∧ b)  ≡  a ∨ b
a ∧ (¬a ∨ b)  ≡  a ∧ b
```

In words, for the first: "`a`, or failing that, `b`" is "`a` or `b`". A table
would confirm it; a derivation shows why. Put the cursor on the first `a`,
preview `:TruthTableDistribute` (`<leader>ttx`), and apply it as a step
(`<leader>ttA`). The new line contains `a ∨ ¬a`, which the complement law
turns into `1`, and the identity law then removes the `1`.

`:TruthTableSimplify` (`<leader>ttz`), which removed the double negations in
earlier lessons, covers every law that shrinks an expression: it finds the
nearest place one of them applies, previews the result, and names the law it
used. Run it on the new line and apply it as a step, then do the same once
more.
]],
            template = [[
a or (not a and b)
]],
            expect = [[
a or (not a and b)
≡ (a ∨ ¬a) ∧ (a ∨ b)    | by distributivity
≡ 1 ∧ (a ∨ b)           | by complement
≡ a ∨ b                 | by identity
]],
            note = [[
Read the justifications down the right: the derivation is three laws you
already had. The second law of the pair goes the same way: distributing `a`
into `¬a ∨ b` gives `a ∧ ¬a ∨ a ∧ b`, then `0 ∨ a ∧ b`, then `a ∧ b`.

Simplify applies one law per run, the nearest to the cursor: first a law that
involves the operand under the cursor, then one inside the group the cursor is
on, then one anywhere on the line.
]],
            solution = {
                { on = "a or (not a and b)", at = "a", run = { "TruthTableDistribute", "TruthTableApplyStep" } },
                {
                    on = "≡ (a ∨ ¬a) ∧ (a ∨ b)    | by distributivity",
                    at = "(a",
                    run = { "TruthTableSimplify", "TruthTableApplyStep" },
                },
                {
                    on = "≡ 1 ∧ (a ∨ b)           | by complement",
                    at = "1",
                    run = { "TruthTableSimplify", "TruthTableApplyStep" },
                },
            },
        },
        {
            text = [[
The derivation was the long way round, taken once to see why the law holds.
Simplify also knows absorption as a law in its own right. The scratch pane
holds the same expression: put the cursor on the first `a`, preview
(`<leader>ttz`), and apply it as a step (`<leader>ttA`).
]],
            template = [[
a or (not a and b)
]],
            expect = [[
a or (not a and b)
≡ a ∨ b               | by absorption
]],
            note = [[
The cursor chose the absorber. On `a`, every term beside it that holds `a` is
absorbed, and every term that holds `¬a` loses it.
]],
            solution = {
                { on = "a or (not a and b)", at = "a", run = { "TruthTableSimplify", "TruthTableApplyStep" } },
            },
        },
        {
            text = [[
*Reduction* removes a variable that appears both plain and negated beside the
same partner:

```text
(a ∧ b) ∨ (¬a ∧ b)  ≡  b
(a ∨ b) ∧ (¬a ∨ b)  ≡  b
```

In words, for the first: if `b` decides the outcome when `a` is true and also
when `a` is false, then `a` has no say. Derive it: with the cursor on either
`b`, preview `:TruthTableFactor` (`<leader>ttf`) and apply it as a step
(`<leader>ttA`). Then simplify twice (`<leader>ttz`), applying each as a step.
]],
            template = [[
(a and b) or (not a and b)
]],
            expect = [[
(a and b) or (not a and b)
≡ b ∧ (a ∨ ¬a)                | by distributivity
≡ b ∧ 1                       | by complement
≡ b                           | by identity
]],
            note = [[
Factor, complement, identity: three laws compressed into one. In code it is
two branches that differ only in whether `a` holds, which make one branch that
never asks about `a`. This is also the law that does the work in the lesson on
Karnaugh maps, where every group of neighbouring cells is a reduction.
]],
            solution = {
                { on = "(a and b) or (not a and b)", at = "b", run = { "TruthTableFactor", "TruthTableApplyStep" } },
                {
                    on = "≡ b ∧ (a ∨ ¬a)                | by distributivity",
                    at = "b",
                    run = { "TruthTableSimplify", "TruthTableApplyStep" },
                },
                {
                    on = "≡ b ∧ 1                       | by complement",
                    at = "b",
                    run = { "TruthTableSimplify", "TruthTableApplyStep" },
                },
            },
        },
        {
            text = [[
The second reduction law is the dual of the first: the same three steps with
`∧` and `∨` traded, and `0` in place of `1`. This time take it in one move.
With the cursor anywhere in either term, preview `:TruthTableSimplify`
(`<leader>ttz`) and apply it as a step.
]],
            template = [[
(a or b) and (not a or b)
]],
            expect = [[
(a or b) and (not a or b)
≡ b                          | by reduction
]],
            note = [[
To see the three steps behind it, undo (`u`) and take the long way: factor
`b` out, then simplify twice.
]],
            solution = {
                { on = "(a or b) and (not a or b)", at = "b", run = { "TruthTableSimplify", "TruthTableApplyStep" } },
            },
        },
    },
}
