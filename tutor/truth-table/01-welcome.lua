return {
    part = "Tables",
    title = "Finding your way around",
    aim = "Learn the tutor's two panes, how its keys are written, and how to move from step to step.",
    steps = {
        {
            text = [=[
This is a short logic course, worked inside the plugin. Each lesson introduces
one idea from propositional logic and the command that goes with it.

The course keeps one use in view: refactoring code. The condition of an `if`,
and any function that returns true or false, is a logic expression, and
changing one safely means knowing that the new version says the same thing as
the old. The examples come back to that question again and again.

The tutor has two panes:

- This one, on the left, is the lesson: what to do in the current step and,
  when the step is an exercise, what you should see once you have done it.
- The one on the right is the scratch pane, where the cursor is now. Each step
  puts its starting text there, and that is where you run the commands. It is
  yours to edit: `u` undoes back to the starting text, and every step keeps
  its own scratch, so your work is still there when you come back to it.

Commands and keys:

A command is given as `:Command`, with its default key after it in
parentheses: `:.TruthTable` (`<leader>ttn`). The key is a sequence: press your
leader key, let it go, then `t`, `t`, `n`. `<leader>` is Neovim's name for the
key you set aside as the prefix of your own mappings: `\` out of the box,
Space in LazyVim and most other distributions. `:echo get(g:, "mapleader", '\')`
prints yours. Every key in this course starts with `<leader>tt`, so with
which-key installed you can press that much and pause: the popup lists the
rest, each with what it does.

Moving around:

- `:TruthTableTutorNext` (`]]` in either pane) goes to the next step, and
  `:TruthTableTutorPrev` (`[[`) to the one before.
- `:TruthTableTutor 5` jumps to the start of lesson 5.
- `:TruthTableTutor` brings you back to your place from anywhere, with your
  work intact. `:TruthTableTutor!` starts the course over with every scratch
  reset.

The course in four parts:

- Tables, lessons 1 to 5: propositions, connectives, and what makes two
  expressions equivalent.
- Rewriting, lessons 6 to 12: the laws of Boolean algebra, derivations that
  record each step, and Karnaugh maps.
- Code, lessons 13 to 18: conditions taken out of JavaScript and Lua,
  rewritten, and put back.
- Reference, lesson 19: every law and command on one page.

The line above this pane says where you are, and stays put while the lesson
scrolls: a bar with a cell per lesson (green for the lessons you have been
to, yellow for this one, grey for those ahead), then the lesson and step,
then the part. Your place outlives Neovim: `:TruthTableTutor` tomorrow opens
where you stopped today. The scratch panes last as long as Neovim does, so
finish an exercise before you quit, or do it again.

Press `]]` to begin.
]=],
            template = [[
This is the scratch pane. Each step's starting text appears here.
]],
        },
    },
}
