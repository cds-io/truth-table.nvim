return {
    title = "Exclusive or, spelled out",
    aim = "Recognise an exclusive or written out with the basic connectives.",
    steps = {
        {
            text = [[
`⊕` can be written with the basic connectives: "exactly one of `t` and `e`" is
"`e` without `t`, or `t` without `e`". Going the other way, spotting that
pattern lets you replace four operands with two. `:TruthTableXor`
(`<leader>tto`) recognises it; the cursor can be anywhere in either term.
Preview, then apply with `<leader>tta`.
]],
            template = [[
(not t and e) or (t and not e)
]],
            expect = [[
t ⊕ e
]],
            note = [[
The same command recognises the pattern for `⇔`, which is `(t ∧ e) ∨ (¬t ∧ ¬e)`:
both true or both false.
]],
            solution = {
                { on = "(not t and e) or (t and not e)", at = "t", run = { "TruthTableXor", "TruthTableApply" } },
            },
        },
    },
}
