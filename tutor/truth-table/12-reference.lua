return {
    title = "Quick reference",
    aim = "Every command from the course in one place, with a scratch pane to try them in.",
    steps = {
        {
            text = [=[
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
