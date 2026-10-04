return {
    title = "De Morgan's laws",
    aim = "Move a negation across `and` and `or`, and use that to make a negated condition say what it requires.",
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
(`<leader>ttd`) previews the result as dimmed text at the end of the line,
followed by the law that justifies it (`⇒ ¬p ∨ ¬q  | by De Morgan`), and
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
So, when does a programmer want this? When a condition is written as what must
not happen. Here is a login check:

```js
function denyLogin({ isActive, hasPassword }) {
  return !(isActive && hasPassword);
}
```

It is correct, and it hides its own content: the reasons a login is denied
sit inside a negation, as their opposites. De Morgan brings them out. Preview
and apply.
]],
            template = [[
not (isActive and hasPassword)
]],
            expect = [[
¬isActive ∨ ¬hasPassword
]],
            note = [[
Read it back into code: `return !isActive || !hasPassword;`. Each reason for
denial is now a term of its own, which is where a specific error message or a
log line would attach.
]],
            solution = {
                { on = "not (isActive and hasPassword)", run = { "TruthTableDeMorgan", "TruthTableApply" } },
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
        {
            text = [[
The opposite complaint is the more common one: a condition written as *reasons
to reject*, wrapped in one big `not`.

```js
function showBanner({ isFreeUser, hasDismissedBanner }) {
  return !(!isFreeUser || hasDismissedBanner);
}
```

"Not (not free, or dismissed)": a reader has to undo two negations in their
head to learn who sees the banner. Pushing the negation inward turns the
reasons to reject into a *list of requirements*. Apply De Morgan
(`<leader>ttd`, then `<leader>tta`). That leaves `¬¬isFreeUser`, and a double
negation cancels:

```text
¬¬p  ≡  p
```

`:TruthTableSimplify` (`<leader>ttz`) previews the cancellation. Apply it too.
]],
            template = [[
not (not isFreeUser or hasDismissedBanner)
]],
            expect = [[
isFreeUser ∧ ¬hasDismissedBanner
]],
            note = [[
`return isFreeUser && !hasDismissedBanner;`: free users who have not dismissed
it. The function is the same, and the condition now reads as the requirement
it is.

Simplify knows more laws than this one. The lesson on absorption and reduction
comes back to it.
]],
            solution = {
                {
                    on = "not (not isFreeUser or hasDismissedBanner)",
                    run = { "TruthTableDeMorgan", "TruthTableApply" },
                },
                { on = "¬¬isFreeUser ∧ ¬hasDismissedBanner", run = { "TruthTableSimplify", "TruthTableApply" } },
            },
        },
    },
}
