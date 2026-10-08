return {
    title = "The arithmetic spelling: sums and products",
    aim = "Read the notation engineering texts use for the same laws, and translate a formula written that way into the plugin's.",
    steps = {
        {
            text = [[
Engineering texts write Boolean algebra in the notation of arithmetic:

| Logic   | Arithmetic | Name       |
|:-------:|:----------:|:-----------|
| `a ∨ b` | `a + b`    | sum        |
| `a ∧ b` | `a · b`    | product    |
| `¬a`    | `a'`       | complement |

Print usually drops the dot, so `ab` is `a · b`, the way `xy` means `x` times
`y`; the formulas below drop it too. The complement is a bar over `a` in
print, and `a'` where a bar is hard to typeset, as it is here. The notation
brings arithmetic's binding order with it: a product groups before a sum, so
`ab + c` is `(a ∧ b) ∨ c`, which is the plugin's order too (`and` before
`or`, from the lesson on connectives).

The plugin reads and writes the logic symbols, so a formula from a textbook or
a datasheet is translated before a table can check it. Here is one:

```text
a'b + ab'
```

Read it product by product: `a'b` is `¬a ∧ b`, `ab'` is `a ∧ ¬b`, and the `+`
is the `or` between them. The scratch pane is empty: give the translation to
`:TruthTable`, with `a xor b` after it as a second column, to see which
connective the formula spells out.
]],
            expect = [[
|  a  |  b  | (¬a ∧ b) ∨ (a ∧ ¬b) | a ⊕ b |
|:---:|:---:|:-------------------:|:-----:|
|  0  |  0  |          0          |   0   |
|  0  |  1  |          1          |   1   |
|  1  |  0  |          1          |   1   |
|  1  |  1  |          0          |   0   |
]],
            note = [[
The two columns agree: `a'b + ab'` is exclusive or, spelled out in `and`, `or`
and `not`, which is how engineering texts usually meet it. The parentheses in
the heading are the plugin's own, around each operand that has a connective
of its own, so the binding order need not be recalled to read it.
]],
            solution = {
                { run = { "TruthTable not a and b or a and not b | a xor b" } },
            },
        },
        {
            text = [[
The six laws from the lesson on constants and complements, in this spelling:

```text
a + 0 = a    a · 1 = a
a + 1 = 1    a · 0 = 0
a + a = a    a · a = a
```

Three read as ordinary arithmetic: `a + 0 = a`, `a · 1 = a` and `a · 0 = 0`
hold for numbers as they stand, and `a · a = a` holds because `0` and `1` are
their own squares. The last two are where logic parts ways with arithmetic:
`a + 1 = 1` and `a + a = a`, since there is no `2` to count up to.

An `or` of `and` terms is a *sum of products* in this spelling, and one can
carry a term it has no need of. Here is one from a digital design text, with
its claimed shorter form:

```text
ab + a'c + bc  =  ab + a'c
```

Translate both sides, give them to `:TruthTable` as two columns, and compare.
]],
            expect = [[
|  a  |  b  |  c  | (a ∧ b) ∨ (¬a ∧ c) ∨ (b ∧ c) | (a ∧ b) ∨ (¬a ∧ c) |
|:---:|:---:|:---:|:----------------------------:|:------------------:|
|  0  |  0  |  0  |              0               |         0          |
|  0  |  0  |  1  |              1               |         1          |
|  0  |  1  |  0  |              0               |         0          |
|  0  |  1  |  1  |              1               |         1          |
|  1  |  0  |  0  |              0               |         0          |
|  1  |  0  |  1  |              0               |         0          |
|  1  |  1  |  0  |              1               |         1          |
|  1  |  1  |  1  |              1               |         1          |
]],
            note = [[
The columns agree: `bc` adds nothing, because whenever `b` and `c` are both
`1`, one of the other two terms already is (`ab` when `a` is `1`, `a'c` when it
is `0`). Finding such a term by eye is the hard part; the lesson on Karnaugh
maps reads it off the column instead, under the name sum of products. (The
law's name, for looking it up: *consensus*.)
]],
            solution = {
                { run = { "TruthTable a and b or not a and c or b and c | a and b or not a and c" } },
            },
        },
    },
}
