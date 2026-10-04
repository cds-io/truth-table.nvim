return {
    title = "Propositions and truth tables",
    aim = "Build a truth table from a list of variable names.",
    steps = {
        {
            text = [[
A *proposition* is a statement that is either true or false: "it is raining",
"the request timed out". Logic names propositions with letters and asks what
follows from combining them. With two propositions `p` and `q` there are four
ways the world can be, and a *truth table* lists them all, one per row, writing
`1` for true and `0` for false.

The line in the scratch pane is a list of variable names. With the cursor on
it, run `:.TruthTable` (`<leader>ttn`). The table takes the line's place.
]],
            template = [[
p q
]],
            expect = [[
|  p  |  q  |
|:---:|:---:|
|  0  |  0  |
|  0  |  1  |
|  1  |  0  |
|  1  |  1  |
]],
            note = [[
The rows count upward in binary (`00`, `01`, `10`, `11`), which is the usual
textbook order. Each new variable doubles the number of rows: `n` variables
give `2^n` of them.
]],
            solution = {
                { on = "p q", run = { ".TruthTable" } },
            },
        },
        {
            text = [[
`:TruthTable` also takes a count. The scratch pane starts empty this time: run
`:TruthTable 3`. The table lands above the cursor line, with variables named
`A`, `B`, `C`.
]],
            expect = [[
|  A  |  B  |  C  |
|:---:|:---:|:---:|
|  0  |  0  |  0  |
|  0  |  0  |  1  |
|  0  |  1  |  0  |
|  0  |  1  |  1  |
|  1  |  0  |  0  |
|  1  |  0  |  1  |
|  1  |  1  |  0  |
|  1  |  1  |  1  |
]],
            solution = {
                { run = { "TruthTable 3" } },
            },
        },
    },
}
