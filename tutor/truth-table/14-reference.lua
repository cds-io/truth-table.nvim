return {
    title = "Quick reference",
    aim = "Every law and command from the course in one place, with a scratch pane to try them in.",
    steps = {
        {
            text = [=[
Laws, each with its dual beside it:

```text
identity      a ∨ 0 ≡ a                      a ∧ 1 ≡ a
domination    a ∨ 1 ≡ 1                      a ∧ 0 ≡ 0
idempotence   a ∨ a ≡ a                      a ∧ a ≡ a
complements   a ∨ ¬a ≡ 1                     a ∧ ¬a ≡ 0
commutative   a ∨ b ≡ b ∨ a                  a ∧ b ≡ b ∧ a
associative   (a ∨ b) ∨ c ≡ a ∨ (b ∨ c)      (a ∧ b) ∧ c ≡ a ∧ (b ∧ c)
distributive  a ∧ (b ∨ c) ≡ a ∧ b ∨ a ∧ c    a ∨ b ∧ c ≡ (a ∨ b) ∧ (a ∨ c)
absorption    a ∨ a ∧ b ≡ a                  a ∧ (a ∨ b) ≡ a
              a ∨ ¬a ∧ b ≡ a ∨ b             a ∧ (¬a ∨ b) ≡ a ∧ b
reduction     a ∧ b ∨ ¬a ∧ b ≡ b             (a ∨ b) ∧ (¬a ∨ b) ≡ b
De Morgan     ¬(a ∧ b) ≡ ¬a ∨ ¬b             ¬(a ∨ b) ≡ ¬a ∧ ¬b
```

Tables:

- `:TruthTable {N or names or expressions}` (`<leader>ttn`): build a table; on
  a line, from that line.
- `:TruthTableExpand {expressions}` (`<leader>tte`): append computed columns.
- `:TruthTableToggle` (`<leader>ttt`): switch `0`/`1` and `F`/`T`.
- `:TruthTableDropRow` (`<leader>ttr`): remove the row under the cursor.
- `:TruthTableDropColumn` (`<leader>ttc`): remove the column under the cursor.
- `:TruthTableKarnaugh` (`<leader>ttk`): Karnaugh map and minimal formula for a
  column.

Rewrites, each a preview at the cursor:

- `:TruthTableDeMorgan` (`<leader>ttd`): De Morgan at the nearest match.
- `:TruthTableCommute[!]` (`<leader>tts`, `<leader>ttS`): swap an operand with
  its neighbour.
- `:TruthTableDistribute` (`<leader>ttx`): distribute an operand into a group.
- `:TruthTableFactor` (`<leader>ttf`): factor an operand out of its terms.
- `:TruthTableXor` (`<leader>tto`): recognise `⊕` or `⇔`.
- `:TruthTableApply` (`<leader>tta`): replace the expression with the preview.
- `:TruthTableApplyStep` (`<leader>ttA`): add the preview below as a `≡` step.

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
