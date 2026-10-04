return {
    title = "From code to logic and back",
    aim = "Tidy a condition from real code, and read the result back into code.",
    steps = {
        {
            text = [[
The reason to do any of this at a keyboard is conditions in code. Here is one,
with four Boolean inputs:

```js
function canAccess({ isSuperAdmin, isAdmin, hasGrant, isClassified }) {
  if (isSuperAdmin) return true;
  if (isAdmin && !isClassified) return true;
  if (hasGrant && !isClassified) return true;
  return false;
}
```

Name the four checks `S`, `A`, `G`, `C`. The function returns true when any of
the three branches fires, which is the expression in the scratch pane. The
repeated `not C` is the thing to tidy. Put the cursor on either `not C`,
preview `:TruthTableFactor` (`<leader>ttf`), and apply it as a step
(`<leader>ttA`); then, with the cursor on `S` in the new line, commute
(`<leader>tts`) and apply that as a step as well.
]],
            template = [[
S or (A and not C) or (G and not C)
]],
            expect = [[
S or (A and not C) or (G and not C)
≡ S ∨ (¬C ∧ (A ∨ G))                   | by distributivity
≡ (¬C ∧ (A ∨ G)) ∨ S                   | by commutativity
]],
            solution = {
                {
                    on = "S or (A and not C) or (G and not C)",
                    at = "not C",
                    run = { "TruthTableFactor", "TruthTableApplyStep" },
                },
                {
                    on = "≡ S ∨ (¬C ∧ (A ∨ G))                   | by distributivity",
                    at = "S",
                    run = { "TruthTableCommute", "TruthTableApplyStep" },
                },
            },
        },
        {
            text = [[
Single letters keep an expression short and a table narrow, which is why logic
uses them. The plugin takes any identifier, though, and with the real names the
result reads straight back into code. The same two steps again: factor with the
cursor on either `not isClassified`, then commute `isSuperAdmin` in the new
line, each applied as a step.
]],
            template = [[
isSuperAdmin or (isAdmin and not isClassified) or (hasGrant and not isClassified)
]],
            expect = [[
isSuperAdmin or (isAdmin and not isClassified) or (hasGrant and not isClassified)
≡ isSuperAdmin ∨ (¬isClassified ∧ (isAdmin ∨ hasGrant))                              | by distributivity
≡ (¬isClassified ∧ (isAdmin ∨ hasGrant)) ∨ isSuperAdmin                              | by commutativity
]],
            note = [[
Read the last line back into code, one name per group:

```js
function canAccess({ isSuperAdmin, isAdmin, hasGrant, isClassified }) {
  const hasAdminOrGrant = isAdmin || hasGrant;
  const canAccessUnclassified = !isClassified && hasAdminOrGrant;
  return canAccessUnclassified || isSuperAdmin;
}
```

The derivation is the argument that the two functions agree, each line with
the law that licenses it. If you would
sooner see it than trust it, put both expressions on one line separated by `|`,
run `:.TruthTable` on it, and compare the columns, as in the lesson on
equivalence.
]],
            solution = {
                {
                    on = "isSuperAdmin or (isAdmin and not isClassified) or (hasGrant and not isClassified)",
                    at = "not isClassified",
                    run = { "TruthTableFactor", "TruthTableApplyStep" },
                },
                {
                    on = "≡ isSuperAdmin ∨ (¬isClassified ∧ (isAdmin ∨ hasGrant))                              | by distributivity",
                    at = "isSuperAdmin",
                    run = { "TruthTableCommute", "TruthTableApplyStep" },
                },
            },
        },
    },
}
