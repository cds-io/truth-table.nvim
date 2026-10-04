return {
    title = "More connectives, and growing a table",
    aim = "Meet `xor`, `implies` and `iff`, and add computed columns to a table you already have.",
    steps = {
        {
            text = [[
Three more connectives round out the set:

- `a xor b` (`a ⊕ b`), exclusive or: true when exactly one of the two is true.
- `a implies b` (`a → b`): false in one case only, when `a` is true and `b` is
  false. A false `a` makes the implication true whatever `b` is, which surprises
  most people the first time. Read it as a promise: "if it rains, I will bring
  an umbrella" is only broken when it rains and there is no umbrella.
- `a iff b` (`a ⇔ b`), "if and only if": true when the two have the same value.

The scratch pane holds a plain two-variable table. Put the cursor anywhere
inside it and run:

    :TruthTableExpand a xor b, a implies b, a iff b

(`<leader>tte` types the command name for you.) Each expression is appended as
a column, computed from the columns already there.
]],
            template = [[
|  a  |  b  |
|:---:|:---:|
|  0  |  0  |
|  0  |  1  |
|  1  |  0  |
|  1  |  1  |
]],
            expect = [[
|  a  |  b  | a ⊕ b | a → b | a ⇔ b |
|:---:|:---:|:-----:|:-----:|:-----:|
|  0  |  0  |   0   |   1   |   1   |
|  0  |  1  |   1   |   1   |   0   |
|  1  |  0  |   1   |   0   |   0   |
|  1  |  1  |   0   |   1   |   1   |
]],
            note = [[
Look at the `a → b` column against the umbrella promise: the single `0` is the
row where `a` is `1` and `b` is `0`.
]],
            solution = {
                { on = "|  a  |  b  |", run = { "TruthTableExpand a xor b, a implies b, a iff b" } },
            },
        },
    },
}
