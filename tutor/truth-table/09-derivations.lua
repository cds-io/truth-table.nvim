return {
    title = "Derivations",
    aim = "Record a chain of rewrites as a derivation, one `≡` line per law, each naming its law.",
    steps = {
        {
            text = [[
A *derivation* is a chain of equivalent expressions, each obtained from the one
before by a law. It shows the reasoning as well as the result.

Any preview can be applied a second way: `:TruthTableApplyStep` (`<leader>ttA`)
leaves the line as it is and writes the rewrite below it as `≡ ...`, followed
by its *justification*, `| by` and the name of the law that takes you from the
line above to this one. It then moves the cursor to the new line so the next
step can start from there.

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
≡ (¬g ∧ ¬h) ∨ (¬g ∧ k)           | by De Morgan
≡ ¬g ∧ (¬h ∨ k)                  | by distributivity
]],
            note = [[
Factoring is the distributive law read right to left, which is why the second
step says distributivity.

Everything from the `|` on is a remark for the reader: a rewrite reads only the
expression before it, and on a line with several `≡`, only the side under the
cursor. To write a step by hand, `equiv@` followed by a space gives the symbol.
]],
            solution = {
                {
                    on = "not (g or h) or (not g and k)",
                    at = "not",
                    run = { "TruthTableDeMorgan", "TruthTableApplyStep" },
                },
                {
                    on = "≡ (¬g ∧ ¬h) ∨ (¬g ∧ k)           | by De Morgan",
                    at = "¬g",
                    run = { "TruthTableFactor", "TruthTableApplyStep" },
                },
            },
        },
        {
            text = [[
Derivations earn their keep on conditions with several negations. This one
decides whether a form can be submitted:

```js
function canSubmit({ hasTitle, hasEmail, isSaving }) {
  return !(!hasTitle || !hasEmail || isSaving);
}
```

Three reasons to reject under one `not`. Turn them into a list of
requirements, one law per line. De Morgan takes two operands at a time, so it
needs two rounds: preview it (`<leader>ttd`) and apply it as a step
(`<leader>ttA`), then do the same again on the new line. Two double negations
are left: simplify (`<leader>ttz`) and apply as a step, twice. Each step
leaves the cursor where the next command needs it.
]],
            template = [[
not (not hasTitle or not hasEmail or isSaving)
]],
            expect = [[
not (not hasTitle or not hasEmail or isSaving)
≡ ¬(¬hasTitle ∨ ¬hasEmail) ∧ ¬isSaving            | by De Morgan
≡ ¬¬hasTitle ∧ ¬¬hasEmail ∧ ¬isSaving             | by De Morgan
≡ hasTitle ∧ ¬¬hasEmail ∧ ¬isSaving               | by double negation
≡ hasTitle ∧ hasEmail ∧ ¬isSaving                 | by double negation
]],
            note = [[
The last line is the refactor: `return hasTitle && hasEmail && !isSaving;`.
The lines above it are the reason to believe it, each a law you can name. In a
code review that is the difference between "I think this is the same" and
showing that it is.
]],
            solution = {
                {
                    on = "not (not hasTitle or not hasEmail or isSaving)",
                    run = { "TruthTableDeMorgan", "TruthTableApplyStep" },
                },
                {
                    on = "≡ ¬(¬hasTitle ∨ ¬hasEmail) ∧ ¬isSaving            | by De Morgan",
                    at = "¬(",
                    run = { "TruthTableDeMorgan", "TruthTableApplyStep" },
                },
                {
                    on = "≡ ¬¬hasTitle ∧ ¬¬hasEmail ∧ ¬isSaving             | by De Morgan",
                    at = "¬¬",
                    run = { "TruthTableSimplify", "TruthTableApplyStep" },
                },
                {
                    on = "≡ hasTitle ∧ ¬¬hasEmail ∧ ¬isSaving               | by double negation",
                    at = "hasTitle",
                    run = { "TruthTableSimplify", "TruthTableApplyStep" },
                },
            },
        },
    },
}
