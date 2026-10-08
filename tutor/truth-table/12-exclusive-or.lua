return {
    title = "Exclusive or, spelled out",
    aim = "Recognise an exclusive or written out with the basic connectives, and decide what to do with one in code.",
    steps = {
        {
            text = [[
`⊕` can be written with the basic connectives: "exactly one of `t` and `e`" is
"`e` without `t`, or `t` without `e`". Going the other way, spotting that
pattern lets you replace four operands with two. `:TruthTableXor`
(`<leader>tto`) recognises it; the cursor can be anywhere in either term, both
in yellow. Preview, then apply with `<leader>tta`.
]],
            template = [[
[:yellow (not t and e)] or [:yellow (t and not e)]
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
        {
            text = [[
In code the pattern turns up as two branches that mirror each other. This
function decides whether to retry a failed request: on a timeout or on a
server error, as long as retries remain, and when both happen at once it gives
up.

```js
function shouldRetry({ isTimeout, isServerError, hasRetries }) {
  if (!isTimeout && isServerError && hasRetries) return true;
  if (isTimeout && !isServerError && hasRetries) return true;
  return false;
}
```

Each branch that returns true is a term, so with `T`, `E`, `R` for the three
checks the function is the expression in the scratch pane. Derive the short
form in three steps, applying each with `<leader>ttA`: factor `R` out (cursor
on either `R`, in yellow, `<leader>ttf`), recognise the exclusive or (cursor
on `¬T`, `<leader>tto`), and commute `R` to the end (cursor on `R`,
`<leader>tts`).
]],
            template = [[
(not T and E and [:yellow R]) or (T and not E and [:yellow R])
]],
            expect = [[
(not T and E and R) or (T and not E and R)
≡ R ∧ ((¬T ∧ E) ∨ (T ∧ ¬E))                   | by distributivity (factoring)
≡ R ∧ (T ⊕ E)                                 | by definition of ⊕
≡ (T ⊕ E) ∧ R                                 | by commutativity
]],
            note = [[
On two Boolean values, `⊕` is `!==`, so the last line reads back as
`return (isTimeout !== isServerError) && hasRetries;`. That is as short as the
logic gets, and a reader still has to stop and decode `!==` between two flags.
When an expression will not shrink any further, name it:

```js
const exactlyOneFailure = isTimeout !== isServerError;
return exactlyOneFailure && hasRetries;
```
]],
            solution = {
                {
                    on = "(not T and E and R) or (T and not E and R)",
                    at = "R",
                    run = { "TruthTableFactor", "TruthTableApplyStep" },
                },
                {
                    on = "≡ R ∧ ((¬T ∧ E) ∨ (T ∧ ¬E))                   | by distributivity (factoring)",
                    at = "¬T",
                    run = { "TruthTableXor", "TruthTableApplyStep" },
                },
                {
                    on = "≡ R ∧ (T ⊕ E)                                 | by definition of ⊕",
                    at = "R",
                    run = { "TruthTableCommute", "TruthTableApplyStep" },
                },
            },
        },
        {
            text = [[
One more proposal arrives in review: "`!==` on booleans is odd, just use
`||`." That is `(T ∨ E) ∧ R` in place of `(T ⊕ E) ∧ R`. The two sound alike,
and the table says what the difference is. Build it.
]],
            template = [[
(T [:blue xor] E) and R | (T [:red or] E) and R
]],
            expect = [[
|  T  |  E  |  R  | (T ⊕ E) ∧ R | (T ∨ E) ∧ R |
|:---:|:---:|:---:|:-----------:|:-----------:|
|  0  |  0  |  0  |      0      |      0      |
|  0  |  0  |  1  |      0      |      0      |
|  0  |  1  |  0  |      0      |      0      |
|  0  |  1  |  1  |      1      |      1      |
|  1  |  0  |  0  |      0      |      0      |
|  1  |  0  |  1  |      1      |      1      |
|  1  |  1  |  0  |      0      |      0      |
|  1  |  1  |  1  |      0      |      1      |
]],
            note = [[
One row differs, the last: both failures at once, with retries left. The
original gives up there, on purpose, and `||` would retry. Whether that row
matters is a question about the system. The table is what turned a remark
about style into a question someone has to answer.
]],
            solution = {
                { on = "(T xor E) and R | (T or E) and R", run = { ".TruthTable" } },
            },
        },
    },
}
