return {
    title = "From code to logic and back",
    aim = "Read a function that returns true or false as one expression, tidy it, and read the result back into code.",
    steps = {
        {
            text = [[
The reason to do any of this at a keyboard is conditions in code, and the
skill that connects the two is reading a function as an expression. A function
that returns only true or false, however many `return`s it has, is one Boolean
expression written as control flow. Read it from the top, one `return` at a
time:

- `if (c) return true;` followed by the rest is `c ∨ rest`.
- `if (c) return false;` followed by the rest is `¬c ∧ rest`.
- A final `return x;` is `x`: `0` for `return false`, `1` for `return true`.

Practise on this one:

```js
function canDelete({ isModerator, isAuthor, isLocked }) {
  if (isModerator) return true;
  if (isAuthor && !isLocked) return true;
  return false;
}
```

Name the checks `M`, `A`, `L` and work out the expression before reading on.
The scratch pane is empty: give your expression to `:TruthTable` and compare
your table with the one below.
]],
            expect = [[
|  M  |  A  |  L  | M ∨ (A ∧ ¬L) |
|:---:|:---:|:---:|:------------:|
|  0  |  0  |  0  |      0       |
|  0  |  0  |  1  |      0       |
|  0  |  1  |  0  |      1       |
|  0  |  1  |  1  |      0       |
|  1  |  0  |  0  |      1       |
|  1  |  0  |  1  |      1       |
|  1  |  1  |  0  |      1       |
|  1  |  1  |  1  |      1       |
]],
            note = [[
The rules give `M ∨ ((A ∧ ¬L) ∨ 0)`, and the identity law drops the `0`. If
your table differs from this one, so does your reading of the function, and
the rows that differ say where.

This is worth practising until it is quick. It is the step that turns "these
two functions look the same" into something you can check, and every refactor
in this lesson starts with it. It also shows why two branches that both return
true are not a single merged condition: `(M ∨ A) ∧ ¬L` is the trap from the
lesson on equivalence, in another function.
]],
            solution = {
                { run = { "TruthTable M or (A and not L)" } },
            },
        },
        {
            text = [[
Guard clauses reject early. Translate this function in three moves:

- **1. Start with the code.** Each guard is a reason to return false.

```js
function canPublish({ hasFatalError, hasTitle, hasTags }) {
  if (hasFatalError) return false;
  if (!hasTitle) return false;
  return hasTags;
}
```

- **2. Name the checks.** Replace `hasFatalError` with `F`, `hasTitle` with
  `T`, and `hasTags` with `G`. Keep the control flow and the `!` unchanged.

```js
if (F) return false;
if (!T) return false;
return G;
```

- **3. Read what must hold for the result to be true.** Both guards must
  let execution continue, and the final return must be true.
- The first guard lets us continue only when `F` is false: `not F`.
- The second guard lets us continue only when its test, `!T`, is false:
  `not (not T)`. The guard contributes one negation; its test already has
  another.
- The final `return G` contributes `G`.
- Join these requirements with `and` because **all three must hold**. If
  either guard fires, the function returns false before reaching `G`.

```text
not F and
not not T and
G
```

Reading from the bottom makes the same construction explicit:

```text
return G                     G
if (!T) return false; rest    not not T and G
if (F) return false; rest     not F and (not not T and G)
```

- **Why `not c and rest`?** When `c` is true the guard returns false. When
  `c` is false the result comes from the rest. The whole result is true only
  when `c` is false **and** the rest is true.
- **Now simplify.** `and` is associative, so the scratch pane writes the
  expression on one line without the grouping parentheses. Simplify
  (`<leader>ttz`) and apply it as a step (`<leader>ttA`).
]],
            template = [[
not F and not not T and G
]],
            expect = [[
not F and not not T and G
≡ ¬F ∧ T ∧ G                 | by double negation
]],
            note = [[
`return !hasFatalError && hasTitle && hasTags;`. The guards and the single
expression are the same function, one written as reasons to reject and the
other as a list of requirements. Knowing that they are the same thing is what
lets you choose: guards when each rejection deserves its own error or log
line, the expression when the rule should be read at a glance.
]],
            solution = {
                { on = "not F and not not T and G", run = { "TruthTableSimplify", "TruthTableApplyStep" } },
            },
        },
        {
            text = [[
Now a larger one, with four Boolean inputs and three ways to say yes:

```js
function canAccess({ isSuperAdmin, isAdmin, hasGrant, isClassified }) {
  if (isSuperAdmin) return true;
  if (isAdmin && !isClassified) return true;
  if (hasGrant && !isClassified) return true;
  return false;
}
```

Name the four checks `S`, `A`, `G`, `C`. Reading from the top, the function
is the three branches joined by `or`, which is the expression in the scratch
pane. The repeated `not C` is the thing to tidy. Put the cursor on either `not C`,
preview `:TruthTableFactor` (`<leader>ttf`), and apply it as a step
(`<leader>ttA`); then, with the cursor on `S` in the new line, commute
(`<leader>tts`) and apply that as a step as well.
]],
            template = [[
S or (A and not C) or (G and not C)
]],
            expect = [[
S or (A and not C) or (G and not C)
≡ S ∨ (¬C ∧ (A ∨ G))                   | by distributivity (factoring)
≡ (¬C ∧ (A ∨ G)) ∨ S                   | by commutativity
]],
            solution = {
                {
                    on = "S or (A and not C) or (G and not C)",
                    at = "not C",
                    run = { "TruthTableFactor", "TruthTableApplyStep" },
                },
                {
                    on = "≡ S ∨ (¬C ∧ (A ∨ G))                   | by distributivity (factoring)",
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
≡ isSuperAdmin ∨ (¬isClassified ∧ (isAdmin ∨ hasGrant))                              | by distributivity (factoring)
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
                    on = "≡ isSuperAdmin ∨ (¬isClassified ∧ (isAdmin ∨ hasGrant))                              | by distributivity (factoring)",
                    at = "isSuperAdmin",
                    run = { "TruthTableCommute", "TruthTableApplyStep" },
                },
            },
        },
    },
}
