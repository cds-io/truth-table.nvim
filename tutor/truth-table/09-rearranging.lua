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
the one to its left). Put the cursor on `m`, in yellow, preview, then apply
with `<leader>tta`.
]],
            template = [[
[:yellow m] and n
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

```logic
[:blue (x ∨ y)] ∨ z  ≡  x ∨ [:blue (y ∨ z)]
[:blue (x ∧ y)] ∧ z  ≡  x ∧ [:blue (y ∧ z)]
```

To test the first with a table, the two groupings have to be kept apart, and
stored columns do that. The table in the scratch pane already has the two
inner groups, the blue ones, `x ∨ y` and `y ∨ z`, computed in columns 4 and 5. With the cursor
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

```logic
[:red u] ∧ (v ∨ w)  ≡  ([:green u] ∧ v) ∨ ([:green u] ∧ w)
[:red u] ∨ (v ∧ w)  ≡  ([:green u] ∨ v) ∧ ([:green u] ∨ w)
```

(The second one has no counterpart in arithmetic: in logic each connective
distributes over the other.)

A law can be used from either of its sides, and here each use has a name for
what happens to `u`. Starting from the left side, `u` moves *in*: the red `u`
outside the group becomes the green `u` in each term. That is *distributing*.
`:TruthTableDistribute` (`<leader>ttx`) moves the operand under the cursor into
the group next to it. Put the cursor on `u`, in yellow, preview, then apply.
]],
            template = [[
[:yellow u] and (v or w)
]],
            expect = [[
(u ∧ v) ∨ (u ∧ w)
]],
            note = [[
The cursor position matters, because the command needs to know which operand
you mean. In `u ∧ (v ∨ w)`, each place the cursor can be selects something
different:

```logic
u ∧ [:blue (v ∨ w)]
u [:red ∧] (v ∨ w)
[:yellow u] ∧ (v ∨ w)
```

On the inner `∨` or either parenthesis it selects the whole group. On the
outer `∧` it selects no operand. On `u` it selects the operand to distribute.
]],
            solution = {
                { on = "u and (v or w)", at = "u", run = { "TruthTableDistribute", "TruthTableApply" } },
            },
        },
        {
            text = [[
Starting from the other side of the same law, the shared operand moves *out*:
the `c` that both terms have is written once, in front, and what is left of
the terms becomes a group. That is *factoring*.

```logic
([:red c] ∧ d) ∨ ([:red c] ∧ e)  ≡  [:green c] ∧ (d ∨ e)
```

`:TruthTableFactor` (`<leader>ttf`) pulls the operand under the cursor out of
every term that has it. Put the cursor on either `c`, in yellow, preview, then
apply.
]],
            template = [[
([:yellow c] and d) or ([:yellow c] and e)
]],
            expect = [[
c ∧ (d ∨ e)
]],
            note = [[
The factor is written first, whichever side of its terms it was on. Factoring
is the one you will reach for most when tidying a condition in code: it turns
a repeated check into a single one.
]],
            solution = {
                { on = "(c and d) or (c and e)", at = "c", run = { "TruthTableFactor", "TruthTableApply" } },
            },
        },
        {
            text = [[
Factoring works with the connectives swapped as well: a shared operand can be
pulled out of `or` groups joined by `and`. Here it undoes a refactor that went
the wrong way: someone distributed a pull-request rule and left this.

```js
function canMerge({ isRepoAdmin, ciPasses, hasBlockingReviews }) {
  return (isRepoAdmin || ciPasses)
    && (isRepoAdmin || !hasBlockingReviews);
}
```

It is correct, and it says the admin check twice. Put the cursor on either
`isRepoAdmin`, in yellow, preview the factoring (`<leader>ttf`), and apply.
]],
            template = [[
([:yellow isRepoAdmin] or ciPasses) and ([:yellow isRepoAdmin] or not hasBlockingReviews)
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
