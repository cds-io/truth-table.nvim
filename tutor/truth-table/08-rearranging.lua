return {
    title = "Rearranging: the commutative, associative and distributive laws",
    aim = "Reorder, regroup, distribute and factor an expression, choosing the operand with the cursor.",
    steps = {
        {
            text = [[
Three more families of laws let you reshape an expression while keeping its
meaning.

The *commutative* laws say order is free: `m ∧ n ≡ n ∧ m`, and the same for
`∨`, `⊕`, and `⇔`. `:TruthTableCommute` (`<leader>tts`) swaps the operand under
the cursor with the one to its right (`:TruthTableCommute!`, `<leader>ttS`, with
the one to its left). Put the cursor on `m`, preview, then apply with
`<leader>tta`.
]],
            template = [[
m and n
]],
            expect = [[
n ∧ m
]],
            solution = {
                { on = "m and n", at = "m", run = { "TruthTableCommute", "TruthTableApply" } },
            },
        },
        {
            text = [[
The *associative* laws say grouping is free too, as long as the connective
stays the same:

```text
(x ∨ y) ∨ z  ≡  x ∨ (y ∨ z)
(x ∧ y) ∧ z  ≡  x ∧ (y ∧ z)
```

The line in the scratch pane holds both groupings of `or`. Build the table
(`:.TruthTable`, `<leader>ttn`) and compare the two computed columns.
]],
            template = [[
(x or y) or z | x or (y or z)
]],
            expect = [[
|  x  |  y  |  z  | (x ∨ y) ∨ z | x ∨ (y ∨ z) |
|:---:|:---:|:---:|:-----------:|:-----------:|
|  0  |  0  |  0  |      0      |      0      |
|  0  |  0  |  1  |      1      |      1      |
|  0  |  1  |  0  |      1      |      1      |
|  0  |  1  |  1  |      1      |      1      |
|  1  |  0  |  0  |      1      |      1      |
|  1  |  0  |  1  |      1      |      1      |
|  1  |  1  |  0  |      1      |      1      |
|  1  |  1  |  1  |      1      |      1      |
]],
            note = [[
Since the grouping makes no difference, a run of one connective is written
without parentheses, `x ∨ y ∨ z`, and the rewrite commands read such a run as
one chain: `:TruthTableCommute` on `y` there gives `x ∨ z ∨ y`. Mixing
connectives is another matter: the lesson on connectives showed that
`p ∨ q ∧ r` and `(p ∨ q) ∧ r` differ.
]],
            solution = {
                { on = "(x or y) or z | x or (y or z)", run = { ".TruthTable" } },
            },
        },
        {
            text = [[
The *distributive* laws relate `∧` and `∨` the way arithmetic relates
multiplication and addition:

```text
u ∧ (v ∨ w)  ≡  u ∧ v ∨ u ∧ w
u ∨ (v ∧ w)  ≡  (u ∨ v) ∧ (u ∨ w)
```

(The second one has no counterpart in arithmetic: in logic each connective
distributes over the other.)

Read left to right, the law *distributes*: `:TruthTableDistribute`
(`<leader>ttx`) multiplies the operand under the cursor into the group next to
it. Put the cursor on `u`, preview, then apply.
]],
            template = [[
u and (v or w)
]],
            expect = [[
u ∧ v ∨ u ∧ w
]],
            note = [[
The cursor position matters, because the command needs to know which operand
you mean. In `u ∧ (v ∨ w)`, the cursor on the inner `∨` or either parenthesis
selects the whole `(v ∨ w)` group. The outer `∧` selects no operand; put the
cursor on `u` to distribute it.
]],
            solution = {
                { on = "u and (v or w)", at = "u", run = { "TruthTableDistribute", "TruthTableApply" } },
            },
        },
        {
            text = [[
Read right to left, the distributive law *factors*: `:TruthTableFactor`
(`<leader>ttf`) pulls the operand under the cursor out of every term that has
it. Put the cursor on either `c`, preview, then apply.
]],
            template = [[
(c and d) or (c and e)
]],
            expect = [[
c ∧ (d ∨ e)
]],
            note = [[
Factoring is the one you will reach for most when tidying a condition in code:
it turns a repeated check into a single one.
]],
            solution = {
                { on = "(c and d) or (c and e)", at = "c", run = { "TruthTableFactor", "TruthTableApply" } },
            },
        },
    },
}
