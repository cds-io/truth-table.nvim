return {
    title = "Finding your way around",
    aim = "Learn the tutor's two panes and how to move from step to step.",
    steps = {
        {
            text = [=[
This is a short logic course, worked inside the plugin. Each lesson introduces
one idea from propositional logic and the command that goes with it.

The tutor has two panes:

- This one, on the left, is the lesson: what to do in the current step and,
  when the step is an exercise, what you should see once you have done it.
- The one on the right is the scratch pane, where the cursor is now. Each step
  puts its starting text there, and that is where you run the commands. It is
  yours to edit: `u` undoes back to the starting text, and every step keeps
  its own scratch, so your work is still there when you come back to it.

Moving around:

- `:TruthTableTutorNext` (`]]` in either pane) goes to the next step, and
  `:TruthTableTutorPrev` (`[[`) to the one before.
- `:TruthTableTutor 5` jumps to the start of lesson 5.
- `:TruthTableTutor` brings you back to your place from anywhere, with your
  work intact. `:TruthTableTutor!` starts the course over with every scratch
  reset.

Commands are given as `:Command`, with the default key in parentheses. The
keys all start with `<leader>tt` (`<leader>` is `\` unless you have set
`mapleader`).

Press `]]` to begin.
]=],
            template = [[
This is the scratch pane. Each step's starting text appears here.
]],
        },
    },
}
