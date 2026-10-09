return {
    title = "Karnaugh maps: a minimal sum of products",
    aim = "Go from a column of ones and zeros back to a compact expression that produces it.",
    steps = {
        {
            text = [[
So far the expressions came first and the tables followed. The reverse question
is the practical one: given a column of ones and zeros, how can we find a
compact expression that produces it? The command finds a *minimal sum of
products*: an `or` of `and` terms, with the fewest terms, then the fewest
variable occurrences (negated or plain). Other forms, such as one using `xor`,
can be shorter still.

Build a table from the line in the scratch pane (`:.TruthTable`). Then put the
cursor in the table's last column and run `:TruthTableKarnaugh`
(`<leader>ttk`). Two things are written below the table.
]],
            template = [[
(A xor B) or (A and C)
]],
            expect = [[
|  A  |  B  |  C  | (A ⊕ B) ∨ (A ∧ C) |
|:---:|:---:|:---:|:-----------------:|
|  0  |  0  |  0  |         0         |
|  0  |  0  |  1  |         0         |
|  0  |  1  |  0  |         1         |
|  0  |  1  |  1  |         1         |
|  1  |  0  |  0  |         1         |
|  1  |  0  |  1  |         1         |
|  1  |  1  |  0  |         0         |
|  1  |  1  |  1  |         1         |

Karnaugh map for (A ⊕ B) ∨ (A ∧ C):

|     |     |     | BC  |     |     |
|:---:|:---:|:---:|:---:|:---:|:---:|
|     |     | 00  | 01  | 11  | 10  |
|  A  |  0  |  0  |  0  |  1  |  1  |
|     |  1  |  1  |  1  |  1  |  0  |

(A ⊕ B) ∨ (A ∧ C) ≡ (¬A ∧ B) ∨ (A ∧ ¬B) ∨ (A ∧ C)
]],
            note = [[
The grid is a *Karnaugh map*: the column's values rearranged so that
neighbouring cells differ in exactly one variable (which is why the columns run
`00 01 11 10` and skip the binary order). A rectangle of ones whose sides are
powers of two is one product term, and a bigger rectangle means a shorter term.
Here the two ones on the right of the top row are `¬A ∧ B`, the two on the left
of the bottom row are `A ∧ ¬B`, and the pair `01`, `11` in the bottom row is
`A ∧ C`. The last line joins them: a minimal sum of products for the column,
written as the head of a derivation.
]],
            solution = {
                { on = "(A xor B) or (A and C)", run = { ".TruthTable" } },
                { on = "|  A  |  B  |  C  | (A ⊕ B) ∨ (A ∧ C) |", at = "(A ⊕", run = { "TruthTableKarnaugh" } },
            },
        },
        {
            text = [[
The formula line invites one more step. Its first two terms are the
exclusive-or pattern from the previous lesson. Put the cursor on `¬A`, in
yellow, preview `:TruthTableXor` (`<leader>tto`), and apply it as a step
(`<leader>ttA`).
]],
            template = [[
(A ⊕ B) ∨ (A ∧ C) ≡ ([:yellow ¬A] ∧ B) ∨ (A ∧ ¬B) ∨ (A ∧ C)
]],
            expect = [[
(A ⊕ B) ∨ (A ∧ C) ≡ (¬A ∧ B) ∨ (A ∧ ¬B) ∨ (A ∧ C)
                  ≡ (A ⊕ B) ∨ (A ∧ C)                | by definition of ⊕
]],
            note = [[
That is the expression the column was built from.

Each group is the reduction law at work. The two cells of the first group are
`¬A ∧ B ∧ C` and `¬A ∧ B ∧ ¬C`: they differ only in `C`, so `C` drops out and
`¬A ∧ B` is left.
]],
            solution = {
                {
                    on = "(A ⊕ B) ∨ (A ∧ C) ≡ (¬A ∧ B) ∨ (A ∧ ¬B) ∨ (A ∧ C)",
                    at = "¬A",
                    run = { "TruthTableXor", "TruthTableApplyStep" },
                },
            },
        },
        {
            text = [[
A map can also tell you there is nothing to find. Take the retry condition
from the last lesson, `(T ⊕ E) ∧ R`: is there a shorter way to write it with
`and`, `or` and `not`? Build the table, then run `:TruthTableKarnaugh`
(`<leader>ttk`) with the cursor in its last column.
]],
            template = [[
(T xor E) and R
]],
            expect = [[
|  T  |  E  |  R  | (T ⊕ E) ∧ R |
|:---:|:---:|:---:|:-----------:|
|  0  |  0  |  0  |      0      |
|  0  |  0  |  1  |      0      |
|  0  |  1  |  0  |      0      |
|  0  |  1  |  1  |      1      |
|  1  |  0  |  0  |      0      |
|  1  |  0  |  1  |      1      |
|  1  |  1  |  0  |      0      |
|  1  |  1  |  1  |      0      |

Karnaugh map for (T ⊕ E) ∧ R:

|     |     |     | ER  |     |     |
|:---:|:---:|:---:|:---:|:---:|:---:|
|     |     | 00  | 01  | 11  | 10  |
|  T  |  0  |  0  |  0  |  1  |  0  |
|     |  1  |  0  |  1  |  0  |  0  |

(T ⊕ E) ∧ R ≡ (¬T ∧ E ∧ R) ∨ (T ∧ ¬E ∧ R)
]],
            note = [[
The two ones sit on a diagonal. Neither has a neighbour to group with, so no
variable drops out, and the minimal sum of products is longer than what you
started with. That is an answer too: this condition does not simplify, and the
thing left to improve in the code is its name (`exactlyOneFailure`).

The formula line is where the last lesson's derivation began: factor `R`,
recognise `⊕`, and you are back at `(T ⊕ E) ∧ R`.
]],
            solution = {
                { on = "(T xor E) and R", run = { ".TruthTable" } },
                { on = "|  T  |  E  |  R  | (T ⊕ E) ∧ R |", at = "(T ⊕", run = { "TruthTableKarnaugh" } },
            },
        },
        {
            text = [[
The map read the sum of products off the column. The same form can be
reached by rewriting instead, with no table: unfold the `⊕`, push each `¬`
onto a variable, distribute `∧` over `∨`, and drop what collapses. That is a
*disjunctive normal form* (an `or` of `and` terms of variables and negated
variables), and `:TruthTableDNF` writes it in one step. With the cursor
anywhere on the line, preview it and apply it as a step (`<leader>ttA`).
`:TruthTableCNF` gives the dual, an `and` of `or` clauses.
]],
            template = [[
(T xor E) and R
]],
            expect = [[
(T xor E) and R
≡ (T ∧ ¬E ∧ R) ∨ (¬T ∧ E ∧ R)    | by disjunctive normal form
]],
            note = [[
The same two terms as the map found, in the order the unfolding met them.
The two routes do not always agree: the rewrite keeps a term that two others
cover (the consensus law from the lesson on the arithmetic spelling), and the
map leaves it out, since a map looks for the fewest groups. When they differ,
the map's answer is the shorter one, and `:TruthTableSimplify` on the
rewrite's answer finds the term to drop.
]],
            solution = {
                { on = "(T xor E) and R", run = { "TruthTableDNF", "TruthTableApplyStep" } },
            },
        },
        {
            text = [[
Rows can be missing, and that is useful. Suppose a door only ever reports
"open" when its key is present, so the state "no key, door open" never occurs.

Build the table from the line in the scratch pane. Put the cursor on the row
where `key` is `0` and `door` is `1`, in the last column. Run
`:TruthTableDropRow` (`<leader>ttr`), then `:TruthTableKarnaugh`.
]],
            template = [[
key and door
]],
            expect = [[
| key | door | key ∧ door |
|:---:|:----:|:----------:|
|  0  |  0   |     0      |
|  1  |  0   |     0      |
|  1  |  1   |     1      |

Karnaugh map for key ∧ door:

|     |     | door |     |
|:---:|:---:|:----:|:---:|
|     |     |  0   |  1  |
| key |  0  |  0   |  X  |
|     |  1  |  0   |  1  |

key ∧ door ≡ door
]],
            note = [[
The missing input shows as `X`, a *don't-care*: the minimiser may count it as a
one or a zero, whichever gives the shorter formula. Counting it as a one lets
the whole `door` column of the map form one group, so the condition shrinks to
a single variable. Here `key ∧ door ≡ door` holds for the allowed states,
under our assumption that an open door requires a key. On the omitted state
(`key = 0`, `door = 1`) the expressions differ, so this is an equivalence under
that assumption, a weaker claim than the unrestricted equivalence the tables
tested earlier.
]],
            solution = {
                { on = "key and door", run = { ".TruthTable" } },
                { on = "|  0  |  1   |     0      |", at = "     0", run = { "TruthTableDropRow", "TruthTableKarnaugh" } },
            },
        },
    },
}
