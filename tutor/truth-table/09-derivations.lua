return {
    title = "Derivations",
    aim = "Record a chain of rewrites as a derivation, one `≡` line per law.",
    steps = {
        {
            text = [[
A *derivation* is a chain of equivalent expressions, each obtained from the one
before by a law. It shows the reasoning as well as the result.

Any preview can be applied a second way: `:TruthTableApplyStep` (`<leader>ttA`)
leaves the line as it is and writes the rewrite below it as `≡ ...`, then moves
the cursor to the new line so the next step can start from there.

Simplify the expression in the scratch pane in two steps. First expand the
negated group: put the cursor on the first `not`, preview De Morgan
(`<leader>ttd`), and apply it as a step (`<leader>ttA`). The cursor is now on
`¬g` in the new line. Both terms contain `¬g`, so factor it out (`<leader>ttf`)
and apply that as a step too.
]],
            template = [[
not (g or h) or (not g and k)
]],
            expect = [[
not (g or h) or (not g and k)
≡ ¬g ∧ ¬h ∨ (¬g ∧ k)
≡ ¬g ∧ (¬h ∨ k)
]],
            note = [[
On a line with several `≡`, a rewrite works on the side under the cursor and
leaves the others alone. To type the symbol yourself, use `equiv@`.
]],
            solution = {
                {
                    on = "not (g or h) or (not g and k)",
                    at = "not",
                    run = { "TruthTableDeMorgan", "TruthTableApplyStep" },
                },
                { on = "≡ ¬g ∧ ¬h ∨ (¬g ∧ k)", at = "¬g", run = { "TruthTableFactor", "TruthTableApplyStep" } },
            },
        },
    },
}
