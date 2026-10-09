return {
    title = "Connectives: not, and, or",
    aim = "Combine propositions with `not`, `and` and `or`, and read the result off a table.",
    steps = {
        {
            text = [[
Propositions combine through *connectives*. The three basic ones:

- `not p` (written `¬p`) is true exactly when `p` is false.
- `p and q` (`p ∧ q`) is true when both are true.
- `p or q` (`p ∨ q`) is true when at least one is true. This is the inclusive
  or: both being true counts.

A table can be built straight from expressions. The variables are the names the
expressions mention, and each expression gets a computed column. Separate the
expressions with `|` or `,`, then run `:.TruthTable` (`<leader>Tn`) on the
line.
]],
            template = [[
p and q | p or q | not p
]],
            expect = [[
|  p  |  q  | p ∧ q | p ∨ q | ¬p  |
|:---:|:---:|:-----:|:-----:|:---:|
|  0  |  0  |   0   |   0   |  1  |
|  0  |  1  |   0   |   1   |  1  |
|  1  |  0  |   0   |   1   |  0  |
|  1  |  1  |   1   |   1   |  0  |
]],
            note = [[
The headings are rendered in logic symbols whichever way you typed them. Both
spellings are accepted as input, and in insert mode the plugin gives you
abbreviations for the symbols: type `and@` followed by a space to get `∧`, and
likewise `or@`, `not@`, `xor@`, `implies@`, `iff@`.
]],
            solution = {
                { on = "p and q | p or q | not p", run = { ".TruthTable" } },
            },
        },
        {
            text = [[
So, what does `p or q and r` mean? Connectives have a binding order, tightest
first: `not`, `and`, `or`, `xor`, `implies`, `iff`. So `and` groups before `or`,
the way multiplication groups before addition, and parentheses override the
order. The line in the scratch pane holds both readings: build the table and
compare the two computed columns.
]],
            template = [[
p or q and r | (p or q) and r
]],
            expect = [[
|  p  |  q  |  r  | p ∨ (q ∧ r) | (p ∨ q) ∧ r |
|:---:|:---:|:---:|:-----------:|:-----------:|
|  0  |  0  |  0  |      0      |      0      |
|  0  |  0  |  1  |      0      |      0      |
|  0  |  1  |  0  |      0      |      0      |
|  0  |  1  |  1  |      1      |      1      |
|  1  |  0  |  0  |      1      |      0      |
|  1  |  0  |  1  |      1      |      1      |
|  1  |  1  |  0  |      1      |      0      |
|  1  |  1  |  1  |      1      |      1      |
]],
            note = [[
The first heading answers the question: `p or q and r` was read as
`p ∨ (q ∧ r)`, with `and` grouped first. The plugin writes an expression back
in one fixed form: an operand that has a connective of its own gets
parentheses, so a heading can be read without recalling the binding order,
and every other parenthesis is left out.

The columns differ in the rows where `p` is true and `r` is false:
`p ∨ (q ∧ r)` is true there because `p` alone is enough, while `(p ∨ q) ∧ r`
needs `r`. The operand that decides each, in blue:

```logic
[:blue p] ∨ (q ∧ r)
(p ∨ q) ∧ [:blue r]
```
]],
            solution = {
                { on = "p or q and r | (p or q) and r", run = { ".TruthTable" } },
            },
        },
    },
}
