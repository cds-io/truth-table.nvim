return {
    title = "More connectives, and growing a table",
    aim = "Meet `xor`, `implies` and `iff`, add computed columns to a table you already have, and tend it: toggle its cells, drop a column, drop a row.",
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

(`<leader>Te` types the command name for you.) Each expression is appended as
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
        {
            text = [[
Three commands tend a table you already have, all with the cursor inside it.
The scratch pane holds the table from the last step.

- `:TruthTableToggle` (`<leader>Tt`) switches the cells between `0`/`1` and
  `F`/`T`. Run it once; running it again switches back.
- `:TruthTableDropColumn` (`<leader>Tc`) removes the column under the cursor.
  Put the cursor in the `a ⇔ b` column, in yellow, and run it.
- `:TruthTableDropRow` (`<leader>Tr`) removes the row under the cursor in the
  same way. Put the cursor on the last row and run it. Either drop is a
  change like any other, so `.` runs it again on whatever the cursor is on
  then: a few rows go with `<leader>Tr` and a few dots.
]],
            template = [[
|  a  |  b  | a ⊕ b | a → b | [:yellow a ⇔ b] |
|:---:|:---:|:-----:|:-----:|:-----:|
|  0  |  0  |   0   |   1   |   1   |
|  0  |  1  |   1   |   1   |   0   |
|  1  |  0  |   1   |   0   |   0   |
|  1  |  1  |   0   |   1   |   1   |
]],
            expect = [[
|  a  |  b  | a ⊕ b | a → b |
|:---:|:---:|:-----:|:-----:|
|  F  |  F  |   F   |   T   |
|  F  |  T  |   T   |   T   |
|  T  |  F  |   T   |   F   |
]],
            note = [[
The table has lost the column that said when `a` and `b` agree, and the row
where both hold. Dropping a row is for a case that cannot occur; the lesson on
Karnaugh maps puts that to use.
]],
            solution = {
                { on = "|  a  |  b  | a ⊕ b | a → b | a ⇔ b |", run = { "TruthTableToggle" } },
                { on = "|  a  |  b  | a ⊕ b | a → b | a ⇔ b |", at = "a ⇔ b", run = { "TruthTableDropColumn" } },
                { on = "|  T  |  T  |   F   |   T   |", run = { "TruthTableDropRow" } },
            },
        },
    },
}
