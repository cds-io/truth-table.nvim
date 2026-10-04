return {
    title = "De Morgan's laws",
    aim = "Move a negation across `and` and `or`, looking at each rewrite before applying it.",
    steps = {
        {
            text = [[
De Morgan's laws say how `not` moves across `and` and `or`:

```text
¬(p ∧ q)  ≡  ¬p ∨ ¬q
¬(p ∨ q)  ≡  ¬p ∧ ¬q
```

In words: "not both" is "at least one is false", and "neither" is "both are
false". The negation moves inward and the connective flips.

The plugin applies the law to an expression on a line of its own. A rewrite
happens in two moves, so you can look before you commit: `:TruthTableDeMorgan`
(`<leader>ttd`) previews the result as dimmed text at the end of the line, and
`:TruthTableApply` (`<leader>tta`) replaces the expression with it. Try it on
the line in the scratch pane.
]],
            template = [[
not (p and q)
]],
            expect = [[
¬p ∨ ¬q
]],
            solution = {
                { on = "not (p and q)", run = { "TruthTableDeMorgan", "TruthTableApply" } },
            },
        },
        {
            text = [[
The law runs in the other direction too, pulling a negation outward. Preview
and apply as before.
]],
            template = [[
not x and not y
]],
            expect = [[
¬(x ∨ y)
]],
            solution = {
                { on = "not x and not y", run = { "TruthTableDeMorgan", "TruthTableApply" } },
            },
        },
        {
            text = [[
Which part is rewritten when an expression has several? The nearest match
around the cursor. Put the cursor on the word `not` before previewing; the
rewrite applies to that group and leaves `r` alone.
]],
            template = [[
r and not (s or t)
]],
            expect = [[
r ∧ ¬s ∧ ¬t
]],
            solution = {
                { on = "r and not (s or t)", at = "not", run = { "TruthTableDeMorgan", "TruthTableApply" } },
            },
        },
    },
}
