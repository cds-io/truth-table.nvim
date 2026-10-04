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
            note = [[
N.B. This is a law about truth values. In code, `a() || b()` evaluates left to
right and stops at the first true operand, so swapping is safe when the
operands are plain values or checks without side effects. It changes behaviour
when `b()` does something, or when the left operand guards the right, as in
`user && user.isAdmin`.
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

To test the first with a table, the two groupings have to be kept apart, and
stored columns do that. The table in the scratch pane already has the two
inner groups, `x ∨ y` and `y ∨ z`, computed in columns 4 and 5. With the cursor
in the table, finish each grouping from its stored column:

    :TruthTableExpand :h4 or z, x or :h5
]],
            template = [[
|  x  |  y  |  z  | x ∨ y | y ∨ z |
|:---:|:---:|:---:|:-----:|:-----:|
|  0  |  0  |  0  |   0   |   0   |
|  0  |  0  |  1  |   0   |   1   |
|  0  |  1  |  0  |   1   |   1   |
|  0  |  1  |  1  |   1   |   1   |
|  1  |  0  |  0  |   1   |   0   |
|  1  |  0  |  1  |   1   |   1   |
|  1  |  1  |  0  |   1   |   1   |
|  1  |  1  |  1  |   1   |   1   |
]],
            expect = [[
|  x  |  y  |  z  | x ∨ y | y ∨ z | “x ∨ y” ∨ z | x ∨ “y ∨ z” |
|:---:|:---:|:---:|:-----:|:-----:|:-----------:|:-----------:|
|  0  |  0  |  0  |   0   |   0   |      0      |      0      |
|  0  |  0  |  1  |   0   |   1   |      1      |      1      |
|  0  |  1  |  0  |   1   |   1   |      1      |      1      |
|  0  |  1  |  1  |   1   |   1   |      1      |      1      |
|  1  |  0  |  0  |   1   |   0   |      1      |      1      |
|  1  |  0  |  1  |   1   |   1   |      1      |      1      |
|  1  |  1  |  0  |   1   |   1   |      1      |      1      |
|  1  |  1  |  1  |   1   |   1   |      1      |      1      |
]],
            note = [[
The last two columns agree in every row. The quotation marks in their headings
mark `“x ∨ y”` as a stored column, used whole.

So, why go through stored columns? Because the plugin takes this law for
granted. Type `(x or y) or z` or `x or (y or z)` and either is written back as
`x ∨ y ∨ z`, a run with no parentheses, since the grouping changes nothing. The
rewrite commands read such a run as one chain: `:TruthTableCommute` on `y`
there gives `x ∨ z ∨ y`.

`⊕` and `⇔` are associative as well, but a flat run of either misleads
(`a ⇔ b ⇔ c` is true when `a` is true and the other two are false, which is far
from "all three agree"), so the plugin keeps their grouping in view:
`(a ⇔ b) ⇔ c`. Mixing connectives is another matter altogether: the lesson on
connectives showed that `p ∨ (q ∧ r)` and `(p ∨ q) ∧ r` differ.
]],
            solution = {
                { on = "|  x  |  y  |  z  | x ∨ y | y ∨ z |", run = { "TruthTableExpand :h4 or z, x or :h5" } },
            },
        },
        {
            text = [[
The *distributive* laws relate `∧` and `∨` the way arithmetic relates
multiplication and addition:

```text
u ∧ (v ∨ w)  ≡  (u ∧ v) ∨ (u ∧ w)
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
(u ∧ v) ∨ (u ∧ w)
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
        {
            text = [[
Factoring works the other way round as well, pulling a shared operand out of
`or` groups joined by `and`. Here it undoes a refactor that went the wrong
way: someone distributed a pull-request rule and left this.

```js
function canMerge({ isRepoAdmin, ciPasses, hasBlockingReviews }) {
  return (isRepoAdmin || ciPasses) && (isRepoAdmin || !hasBlockingReviews);
}
```

It is correct, and it says the admin check twice. Put the cursor on either
`isRepoAdmin`, preview the factoring (`<leader>ttf`), and apply.
]],
            template = [[
(isRepoAdmin or ciPasses) and (isRepoAdmin or not hasBlockingReviews)
]],
            expect = [[
isRepoAdmin ∨ (ciPasses ∧ ¬hasBlockingReviews)
]],
            note = [[
Admins can merge; everyone else needs passing CI and no blocking reviews. In
code the inner group wants a name:

```js
const isUnblocked = ciPasses && !hasBlockingReviews;
return isRepoAdmin || isUnblocked;
```

Equivalent forms are not equally readable. The laws let you move between them
and pick the one that says what the rule is.
]],
            solution = {
                {
                    on = "(isRepoAdmin or ciPasses) and (isRepoAdmin or not hasBlockingReviews)",
                    at = "isRepoAdmin",
                    run = { "TruthTableFactor", "TruthTableApply" },
                },
            },
        },
    },
}
