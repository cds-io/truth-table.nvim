return {
    title = "Absorption and reduction",
    aim = "Shrink an expression with the absorption and reduction laws, and derive them from the laws before.",
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

The rewrite commands cover the laws that rearrange; the complement and
identity steps you write by hand. Open a line below with `o` and type each of
the last two lines shown.
]],
            template = [[
a or (not a and b)
]],
            expect = [[
a or (not a and b)
≡ (a ∨ ¬a) ∧ (a ∨ b)
≡ 1 ∧ (a ∨ b)
≡ a ∨ b
]],
            note = [[
In insert mode `equiv@`, `and@` and `or@`, each followed by a space, give the
symbols; the words `and` and `or` are read just as well. To check a step you
wrote yourself, put its two sides on a line separated by `|` and build the
table. The second law of the pair goes the same way: distributing `a` into
`¬a ∨ b` gives `a ∧ ¬a ∨ a ∧ b`, then `0 ∨ a ∧ b`, then `a ∧ b`.
]],
            solution = {
                { on = "a or (not a and b)", at = "a", run = { "TruthTableDistribute", "TruthTableApplyStep" } },
                { on = "≡ (a ∨ ¬a) ∧ (a ∨ b)", run = { "normal! o≡ 1 ∧ (a ∨ b)", "normal! o≡ a ∨ b" } },
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
(`<leader>ttA`). Then write the complement step and the identity step below
it, as before.
]],
            template = [[
(a and b) or (not a and b)
]],
            expect = [[
(a and b) or (not a and b)
≡ b ∧ (a ∨ ¬a)
≡ b ∧ 1
≡ b
]],
            note = [[
Factor, complement, identity: three laws compressed into one. This is the law
that does the work in the lesson on Karnaugh maps, where every group of
neighbouring cells is a reduction.
]],
            solution = {
                { on = "(a and b) or (not a and b)", at = "b", run = { "TruthTableFactor", "TruthTableApplyStep" } },
                { on = "≡ b ∧ (a ∨ ¬a)", run = { "normal! o≡ b ∧ 1", "normal! o≡ b" } },
            },
        },
        {
            text = [[
The second reduction law is the dual of the first, and so is its derivation:
the same three steps with `∧` and `∨` traded, and `0` in place of `1`. Factor
`b` out (cursor on either `b`, `<leader>ttf`) and apply it as a step,
then write the complement step (`a ∧ ¬a` is `0`) and the identity step
(`b ∨ 0` is `b`).
]],
            template = [[
(a or b) and (not a or b)
]],
            expect = [[
(a or b) and (not a or b)
≡ b ∨ (a ∧ ¬a)
≡ b ∨ 0
≡ b
]],
            solution = {
                { on = "(a or b) and (not a or b)", at = "b", run = { "TruthTableFactor", "TruthTableApplyStep" } },
                { on = "≡ b ∨ (a ∧ ¬a)", run = { "normal! o≡ b ∨ 0", "normal! o≡ b" } },
            },
        },
    },
}
