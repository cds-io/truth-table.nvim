return {
    title = "Quick reference",
    aim = "Every law, reading rule and command from the course in one place, with a scratch pane to try them in.",
    steps = {
        {
            text = [=[
Laws, each with its dual beside it (below it, for the distributive pair),
under the name a preview or a step's `| by` gives it:

```text
identity         a ∨ 0 ≡ a                      a ∧ 1 ≡ a
domination       a ∨ 1 ≡ 1                      a ∧ 0 ≡ 0
idempotence      a ∨ a ≡ a                      a ∧ a ≡ a
complement       a ∨ ¬a ≡ 1                     a ∧ ¬a ≡ 0
commutativity    a ∨ b ≡ b ∨ a                  a ∧ b ≡ b ∧ a
associativity    (a ∨ b) ∨ c ≡ a ∨ (b ∨ c)      (a ∧ b) ∧ c ≡ a ∧ (b ∧ c)
distributivity   a ∧ (b ∨ c) ≡ (a ∧ b) ∨ (a ∧ c)
                 a ∨ (b ∧ c) ≡ (a ∨ b) ∧ (a ∨ c)
absorption       a ∨ (a ∧ b) ≡ a                a ∧ (a ∨ b) ≡ a
                 a ∨ (¬a ∧ b) ≡ a ∨ b           a ∧ (¬a ∨ b) ≡ a ∧ b
reduction        (a ∧ b) ∨ (¬a ∧ b) ≡ b         (a ∨ b) ∧ (¬a ∨ b) ≡ b
De Morgan        ¬(a ∧ b) ≡ ¬a ∨ ¬b             ¬(a ∨ b) ≡ ¬a ∧ ¬b
double negation  ¬¬a ≡ a
```

A function that returns true or false, read from the top as one expression,
and the condition each branch of an `if` runs under (the syntax is beside the
point: `if c then return true end` in Lua reads the same way):

```text
if (c) return true;   rest      c ∨ rest
if (c) return false;  rest      ¬c ∧ rest
return x;                       x

if (a) X                        X runs when a
else if (b) Y                   Y runs when ¬a ∧ b
else Z                          Z runs when ¬a ∧ ¬b
```

From code to an expression and back, in five stages:

- **1. Name the checks.** Find the smallest tests the code makes and give
  each a letter.
- **2. Translate.** Write the code as an expression in those letters.
- **3. Rewrite or compare.** Apply the laws, one step per line, or compare
  expressions with a table. Exclude impossible rows only when an input
  constraint justifies it; the result then holds under that constraint.
- **4. Back into the code.** Put the tests back in place of the letters, turn
  negated comparisons around (`¬(x < y)` is `x >= y` for the positions in
  these examples), and write it out. Check evaluation order and, when the
  expression selects a value, the value returned as well as its truthiness.
- **5. Review.** Before and after, side by side: what the change buys and
  what it costs.

Tables:

- `:TruthTable {N or names or expressions}` (`<leader>ttn`): build a table; on
  a line, from that line.
- `:TruthTableExpand {expressions}` (`<leader>tte`): append computed columns.
- `:TruthTableToggle` (`<leader>ttt`): switch `0`/`1` and `F`/`T`.
- `:TruthTableDropRow` (`<leader>ttr`): remove the row under the cursor.
- `:TruthTableDropColumn` (`<leader>ttc`): remove the column under the cursor.
- `:TruthTableKarnaugh` (`<leader>ttk`): Karnaugh map and minimal formula for a
  column.

Rewrites, each a preview at the cursor that names its law:

- `:TruthTableDeMorgan` (`<leader>ttd`): De Morgan at the nearest match.
- `:TruthTableCommute[!]` (`<leader>tts`, `<leader>ttS`): swap an operand with
  its neighbour.
- `:TruthTableDistribute` (`<leader>ttx`): distribute an operand into a group.
- `:TruthTableFactor` (`<leader>ttf`): factor an operand out of its terms.
- `:TruthTableXor` (`<leader>tto`): recognise `⊕` or `⇔`.
- `:TruthTableSimplify` (`<leader>ttz`): apply the nearest shrinking law:
  complement, identity, domination, idempotence, absorption or reduction.
- `:TruthTableApply` (`<leader>tta`): replace the expression with the preview.
- `:TruthTableApplyStep` (`<leader>ttA`): add the preview below as a `≡` step
  with its `| by` justification.
- `:TruthTableRewrites` (`<leader>ttl`): list every rewrite of the expression,
  wherever it applies, and add the one you pick as a `≡` step.

The tutor:

- `:TruthTableTutor[!] [lesson]`: return to your place, start over with `!`, or
  jump to a lesson.
- `:TruthTableTutorNext` (`]]`), `:TruthTableTutorPrev` (`[[`): move one step.

`:help truth-table` has the full reference, including the parts this course
skipped: escaping in headings, the rules for which columns a Karnaugh map reads
as inputs, and configuring the abbreviations.
]=],
        },
    },
}
