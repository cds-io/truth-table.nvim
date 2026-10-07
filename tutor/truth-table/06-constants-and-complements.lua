return {
    title = "Constants and complements",
    aim = "Learn what `or` and `and` do with `1`, `0`, a repeated operand, and an operand's own negation.",
    steps = {
        {
            text = [[
An expression can be a constant: the proposition that is true in every row (a
tautology with no variables in it), or the one that is false in every row.
Each has two spellings. `1` and `0` are the ones a table's cells use; `⊤` and
`⊥` ("top" and "bottom") are the ones logic texts use. They mean the same
thing, and the plugin reads both.

The laws of *Boolean algebra*, the rules for rewriting one expression into an
equivalent one, start with what `or` does when it already knows one of its
operands. Here they are in each spelling, the operand that drops out in red:

```logic
[:red a] ∨ 1  ≡  1        [:red a] ∨ ⊤  ≡  ⊤
a ∨ [:red 0]  ≡  a        a ∨ [:red ⊥]  ≡  a
a ∨ [:red a]  ≡  a
```

In words: once one side of an `or` is true, the other side has no say; a false
side contributes nothing, so the result is the other side; and saying a thing
twice says it once. (The names, for looking them up: *domination*, *identity*
and *idempotence*.)

The scratch pane holds the three left-hand sides twice, once per spelling.
Build a table from each line (`:.TruthTable`, `<leader>ttn`, with the cursor
on the line) and compare each computed column with its law.
]],
            template = [[
a or 1 | a or 0 | a or a

a or ⊤ | a or ⊥ | a or a
]],
            expect = [[
|  a  | a ∨ 1 | a ∨ 0 | a ∨ a |
|:---:|:-----:|:-----:|:-----:|
|  0  |   1   |   0   |   0   |
|  1  |   1   |   1   |   1   |

|  a  | a ∨ ⊤ | a ∨ ⊥ | a ∨ a |
|:---:|:-----:|:-----:|:-----:|
|  0  |   1   |   0   |   0   |
|  1  |   1   |   1   |   1   |
]],
            note = [[
The two tables agree cell for cell: the spelling changes the headings and
nothing else. In both, the column for `a ∨ 1` is all ones, and the other two
repeat the `a` column.

These laws look too obvious to need stating, and they are what a refactor
leaves behind when a value becomes known: inside `if (isAdmin) { ... }`, the
condition `isAdmin || hasGrant` is `1 ∨ hasGrant`, which is `1`, and the check
can go.

A heading keeps the spelling you typed. The words `true` and `false` are read
as well, and rendered as `⊤` and `⊥`, the way `and` is rendered as `∧`; in
insert mode, `true@` and `false@` followed by a space give the symbols
directly. From here on the course writes `1` and `0`, to match the cells.
]],
            solution = {
                { on = "a or 1 | a or 0 | a or a", run = { ".TruthTable" } },
                { on = "a or ⊤ | a or ⊥ | a or a", run = { ".TruthTable" } },
            },
        },
        {
            text = [[
`and` has the same three laws, with the constants trading places; again the
red operand drops out:

```logic
a ∧ [:red 1]  ≡  a
[:red a] ∧ 0  ≡  0
a ∧ [:red a]  ≡  a
```

The trade is a pattern, called *duality*: take any law, swap `∧` with `∨` and
`1` with `0`, and the result is another law. Every law from here on comes as
such a pair. Build the table and check the three columns.
]],
            template = [[
a and 1 | a and 0 | a and a
]],
            expect = [[
|  a  | a ∧ 1 | a ∧ 0 | a ∧ a |
|:---:|:-----:|:-----:|:-----:|
|  0  |   0   |   0   |   0   |
|  1  |   1   |   0   |   1   |
]],
            note = [[
Engineering texts write these laws in the notation of arithmetic: `a + b` for
`a ∨ b`, `ab` for `a ∧ b`, and a bar over `a` for `¬a`. Three of the six laws
then read as ordinary arithmetic (`a + 0 = a`, `a1 = a`, `a0 = 0`), and
`aa = a` holds because `a` is only ever `0` or `1`. The last two are where
logic parts ways with arithmetic: `a + 1 = 1` and `a + a = a`, since there is
no `2` to count up to. The plugin reads and writes the logic symbols. The
arithmetic spelling is why an `or` of `and` terms is called a *sum of
products*, a name that returns in the lesson on Karnaugh maps.
]],
            solution = {
                { on = "a and 1 | a and 0 | a and a", run = { ".TruthTable" } },
            },
        },
        {
            text = [[
The *complement* of `a` is its negation, `¬a`. A proposition and its
complement cover every case between them, and never hold together: the blue
pair is the green constant.

```logic
[:blue a ∨ ¬a]  ≡  [:green 1]
[:blue a ∧ ¬a]  ≡  [:green 0]
```

The second is the contradiction from the lesson on equivalence; the first is
its dual, a tautology. Build the table to see both.
]],
            template = [[
a or not a | a and not a
]],
            expect = [[
|  a  | a ∨ ¬a | a ∧ ¬a |
|:---:|:------:|:------:|
|  0  |   1    |   0    |
|  1  |   1    |   0    |
]],
            note = [[
These two laws are how a variable leaves an expression: once a rewrite brings
`a` and `¬a` together, the pair collapses to a constant, and the identity laws
remove the constant. The lesson on absorption and reduction works that way.
]],
            solution = {
                { on = "a or not a | a and not a", run = { ".TruthTable" } },
            },
        },
    },
}
