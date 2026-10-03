# truth-table.nvim tutor

A short logic course, worked inside the plugin. Each lesson introduces one idea
from propositional logic and the command that goes with it, and every exercise
runs on a line of this buffer.

How to use it:

- This buffer is a scratch copy, so edit it freely. `:TruthTableTutor` brings you
  back to it with your work intact; `:TruthTableTutor!` starts a fresh copy.
- Commands are given as `:Command`, with the default key in parentheses. The keys
  all start with `<leader>tt` (`<leader>` is `\` unless you have set `mapleader`).
- After each exercise there is a fenced block showing what you should see. The
  table commands ignore tables inside a fence, so those blocks stay as they are
  and you can compare against them.

## 1. Propositions and truth tables

A *proposition* is a statement that is either true or false: "it is raining",
"the request timed out". Logic names propositions with letters and asks what
follows from combining them. With two propositions `p` and `q` there are four
ways the world can be, and a *truth table* lists them all, one per row, writing
`1` for true and `0` for false.

Put the cursor on the line below and run `:.TruthTable` (`<leader>ttn`). The
line is the list of variable names, and the table takes its place.

p q

```text
|  p  |  q  |
|:---:|:---:|
|  0  |  0  |
|  0  |  1  |
|  1  |  0  |
|  1  |  1  |
```

The rows count upward in binary (`00`, `01`, `10`, `11`), which is the usual
textbook order. Each new variable doubles the number of rows: `n` variables
give `2^n` of them.

`:TruthTable` also takes a count. With the cursor on the marker line below, run
`:TruthTable 3`. The table lands above the cursor line, with variables named
`A`, `B`, `C`.

(your three-variable table goes above this line)

```text
|  A  |  B  |  C  |
|:---:|:---:|:---:|
|  0  |  0  |  0  |
|  0  |  0  |  1  |
|  0  |  1  |  0  |
|  0  |  1  |  1  |
|  1  |  0  |  0  |
|  1  |  0  |  1  |
|  1  |  1  |  0  |
|  1  |  1  |  1  |
```

## 2. Connectives: not, and, or

Propositions combine through *connectives*. The three basic ones:

- `not p` (written `¬p`) is true exactly when `p` is false.
- `p and q` (`p ∧ q`) is true when both are true.
- `p or q` (`p ∨ q`) is true when at least one is true. This is the inclusive
  or: both being true counts.

A table can be built straight from expressions. The variables are the names the
expressions mention, and each expression gets a computed column. Separate the
expressions with `|` or `,`, then run `:.TruthTable` (`<leader>ttn`) on the line:

p and q | p or q | not p

```text
|  p  |  q  | p ∧ q | p ∨ q | ¬p  |
|:---:|:---:|:-----:|:-----:|:---:|
|  0  |  0  |   0   |   0   |  1  |
|  0  |  1  |   0   |   1   |  1  |
|  1  |  0  |   0   |   1   |  0  |
|  1  |  1  |   1   |   1   |  0  |
```

The headings are rendered in logic symbols whichever way you typed them. Both
spellings are accepted as input, and in insert mode the plugin gives you
abbreviations for the symbols: type `and@` followed by a space to get `∧`, and
likewise `or@`, `not@`, `xor@`, `implies@`, `iff@`.

So, what does `p or q and r` mean? Connectives have a binding order, tightest
first: `not`, `and`, `or`, `xor`, `implies`, `iff`. So `and` groups before `or`,
the way multiplication groups before addition, and parentheses override the
order. Build both readings and compare the two computed columns:

p or q and r | (p or q) and r

```text
|  p  |  q  |  r  | p ∨ q ∧ r | (p ∨ q) ∧ r |
|:---:|:---:|:---:|:---------:|:-----------:|
|  0  |  0  |  0  |     0     |      0      |
|  0  |  0  |  1  |     0     |      0      |
|  0  |  1  |  0  |     0     |      0      |
|  0  |  1  |  1  |     1     |      1      |
|  1  |  0  |  0  |     1     |      0      |
|  1  |  0  |  1  |     1     |      1      |
|  1  |  1  |  0  |     1     |      0      |
|  1  |  1  |  1  |     1     |      1      |
```

They differ in the rows where `p` is true and `r` is false: `p ∨ q ∧ r` is true
there because `p` alone is enough, while `(p ∨ q) ∧ r` needs `r`.

## 3. More connectives, and growing a table

Three more connectives round out the set:

- `a xor b` (`a ⊕ b`), exclusive or: true when exactly one of the two is true.
- `a implies b` (`a → b`): false in one case only, when `a` is true and `b` is
  false. A false `a` makes the implication true whatever `b` is, which surprises
  most people the first time. Read it as a promise: "if it rains, I will bring
  an umbrella" is only broken when it rains and there is no umbrella.
- `a iff b` (`a ⇔ b`), "if and only if": true when the two have the same value.

Start with a plain two-variable table (`:.TruthTable` on the line):

a b

```text
|  a  |  b  |
|:---:|:---:|
|  0  |  0  |
|  0  |  1  |
|  1  |  0  |
|  1  |  1  |
```

Now put the cursor anywhere inside that table and run:

    :TruthTableExpand a xor b, a implies b, a iff b

(`<leader>tte` types the command name for you.) Each expression is appended as
a column, computed from the columns already there:

```text
|  a  |  b  | a ⊕ b | a → b | a ⇔ b |
|:---:|:---:|:-----:|:-----:|:-----:|
|  0  |  0  |   0   |   1   |   1   |
|  0  |  1  |   1   |   1   |   0   |
|  1  |  0  |   1   |   0   |   0   |
|  1  |  1  |   0   |   1   |   1   |
```

Look at the `a → b` column against the umbrella promise: the single `0` is the
row where `a` is `1` and `b` is `0`.

## 4. Equivalence, tautology, contradiction

Two expressions are *logically equivalent* when they have the same truth value
in every row: no state of the world can tell them apart. The table is the test.
Here is a claim to check: `a → b` says the same thing as `¬a ∨ b`.

a implies b | not a or b

```text
|  a  |  b  | a → b | ¬a ∨ b |
|:---:|:---:|:-----:|:------:|
|  0  |  0  |   1   |   1    |
|  0  |  1  |   1   |   1    |
|  1  |  0  |   0   |   0    |
|  1  |  1  |   1   |   1    |
```

The two computed columns match row for row, so the claim holds. Equivalence is
written `≡`: `a → b ≡ ¬a ∨ b`.

There is a second way to see it. `⇔` is true when its two sides agree, so the
`⇔` of two equivalent expressions is true in every row. An expression that is
true in every row is a *tautology*. With the cursor in the table, add that
column. `:h3` and `:h4` refer to the third and fourth columns by position, which
saves retyping them:

    :TruthTableExpand :h3 iff :h4

```text
|  a  |  b  | a → b | ¬a ∨ b | “a → b” ⇔ “¬a ∨ b” |
|:---:|:---:|:-----:|:------:|:------------------:|
|  0  |  0  |   1   |   1    |         1          |
|  0  |  1  |   1   |   1    |         1          |
|  1  |  0  |   0   |   0    |         1          |
|  1  |  1  |   1   |   1    |         1          |
```

All ones. The opposite of a tautology is a *contradiction*, an expression that
is false in every row. The simplest one says a thing is both true and not true:

    :TruthTableExpand a and not a

```text
|  a  |  b  | a → b | ¬a ∨ b | “a → b” ⇔ “¬a ∨ b” | a ∧ ¬a |
|:---:|:---:|:-----:|:------:|:------------------:|:------:|
|  0  |  0  |   1   |   1    |         1          |   0    |
|  0  |  1  |   1   |   1    |         1          |   0    |
|  1  |  0  |   0   |   0    |         1          |   0    |
|  1  |  1  |   1   |   1    |         1          |   0    |
```

Three table commands are worth knowing while this table is in front of you, all
with the cursor inside it:

- `:TruthTableToggle` (`<leader>ttt`) switches the cells between `0`/`1` and
  `F`/`T`. Run it once to get the table below, and again to switch back.

```text
|  a  |  b  | a → b | ¬a ∨ b | “a → b” ⇔ “¬a ∨ b” | a ∧ ¬a |
|:---:|:---:|:-----:|:------:|:------------------:|:------:|
|  F  |  F  |   T   |   T    |         T          |   F    |
|  F  |  T  |   T   |   T    |         T          |   F    |
|  T  |  F  |   F   |   F    |         T          |   F    |
|  T  |  T  |   T   |   T    |         T          |   F    |
```

- `:TruthTableDropColumn` (`<leader>ttc`) removes the column under the cursor.
  Put the cursor in the `a ∧ ¬a` column and run it; the table returns to the
  five columns it had before.
- `:TruthTableDropRow` (`<leader>ttr`) removes the row under the cursor. Lesson 9
  puts that to use.

## 5. De Morgan's laws

De Morgan's laws say how `not` moves across `and` and `or`:

```text
¬(p ∧ q)  ≡  ¬p ∨ ¬q
¬(p ∨ q)  ≡  ¬p ∧ ¬q
```

In words: "not both" is "at least one is false", and "neither" is "both are
false". The negation moves inward and the connective flips.

The plugin applies the law to an expression on a line of its own. A rewrite
happens in two moves, so you can look before you commit: `:TruthTableDeMorgan`
(`<leader>ttd`) previews the result as dimmed text at the end of the line, and
`:TruthTableApply` (`<leader>tta`) replaces the expression with it. Try it:

not (p and q)

```text
¬p ∨ ¬q
```

The law runs in the other direction too, pulling a negation outward:

not x and not y

```text
¬(x ∨ y)
```

Which part is rewritten when an expression has several? The nearest match
around the cursor. On the line below, put the cursor on the word `not` before
previewing; the rewrite applies to that group and leaves `r` alone:

r and not (s or t)

```text
r ∧ ¬s ∧ ¬t
```

## 6. Rearranging: the commutative and distributive laws

Two more families of laws let you reshape an expression while keeping its
meaning.

The *commutative* laws say order is free: `m ∧ n ≡ n ∧ m`, and the same for
`∨`, `⊕`, and `⇔`. `:TruthTableCommute` (`<leader>tts`) swaps the operand under
the cursor with the one to its right (`:TruthTableCommute!`, `<leader>ttS`, with
the one to its left). Put the cursor on `m`, preview, then apply with
`<leader>tta`:

m and n

```text
n ∧ m
```

The *distributive* laws relate `∧` and `∨` the way arithmetic relates
multiplication and addition:

```text
u ∧ (v ∨ w)  ≡  u ∧ v ∨ u ∧ w
u ∨ (v ∧ w)  ≡  (u ∨ v) ∧ (u ∨ w)
```

(The second one has no counterpart in arithmetic: in logic each connective
distributes over the other.)

Read left to right, the law *distributes*: `:TruthTableDistribute`
(`<leader>ttx`) multiplies the operand under the cursor into the group next to
it. Cursor on `u`:

u and (v or w)

```text
u ∧ v ∨ u ∧ w
```

Read right to left, it *factors*: `:TruthTableFactor` (`<leader>ttf`) pulls the
operand under the cursor out of every term that has it. Cursor on either `c`:

(c and d) or (c and e)

```text
c ∧ (d ∨ e)
```

Factoring is the one you will reach for most when tidying a condition in code:
it turns a repeated check into a single one.

These three commands need to know which operand you mean, so the cursor
position matters. In `u ∧ (v ∨ w)`, the cursor on the inner `∨` or either
parenthesis selects the whole `(v ∨ w)` group. The outer `∧` selects no operand;
put the cursor on `u` to distribute it.

## 7. Derivations

A *derivation* is a chain of equivalent expressions, each obtained from the one
before by a law. It shows the reasoning as well as the result.

Any preview can be applied a second way: `:TruthTableApplyStep` (`<leader>ttA`)
leaves the line as it is and writes the rewrite below it as `≡ ...`, then moves
the cursor to the new line so the next step can start from there.

Simplify the expression below in two steps. First expand the negated group: put
the cursor on the first `not`, preview De Morgan (`<leader>ttd`), and apply it
as a step (`<leader>ttA`). The cursor is now on `¬g` in the new line. Both terms
contain `¬g`, so factor it out (`<leader>ttf`) and apply that as a step too.

not (g or h) or (not g and k)

```text
not (g or h) or (not g and k)
≡ ¬g ∧ ¬h ∨ (¬g ∧ k)
≡ ¬g ∧ (¬h ∨ k)
```

On a line with several `≡`, a rewrite works on the side under the cursor and
leaves the others alone. To type the symbol yourself, use `equiv@`.

## 8. Exclusive or, spelled out

`⊕` can be written with the basic connectives: "exactly one of `t` and `e`" is
"`e` without `t`, or `t` without `e`". Going the other way, spotting that
pattern lets you replace four operands with two. `:TruthTableXor`
(`<leader>tto`) recognises it; the cursor can be anywhere in either term.
Preview, then apply with `<leader>tta`:

(not t and e) or (t and not e)

```text
t ⊕ e
```

The same command recognises the pattern for `⇔`, which is `(t ∧ e) ∨ (¬t ∧ ¬e)`:
both true or both false.

## 9. Karnaugh maps: a minimal sum of products

So far the expressions came first and the tables followed. The reverse question
is the practical one: given a column of ones and zeros, how can we find a
compact expression that produces it? The command finds a *minimal sum of
products*: an `or` of `and` terms, with the fewest terms, then the fewest
variable occurrences (negated or plain). Other forms, such as one using `xor`,
can be shorter still.

Build a table with a computed column:

(A xor B) or (A and C)

```text
|  A  |  B  |  C  | (A ⊕ B) ∨ (A ∧ C) |
|:---:|:---:|:---:|:-----------------:|
|  0  |  0  |  0  |         0         |
|  0  |  0  |  1  |         0         |
|  0  |  1  |  0  |         1         |
|  0  |  1  |  1  |         1         |
|  1  |  0  |  0  |         1         |
|  1  |  0  |  1  |         1         |
|  1  |  1  |  0  |         0         |
|  1  |  1  |  1  |         1         |
```

Now put the cursor in the last column and run `:TruthTableKarnaugh`
(`<leader>ttk`). Two things are written below the table:

```text
Karnaugh map for (A ⊕ B) ∨ (A ∧ C):

|     |     |     | BC  |     |     |
|:---:|:---:|:---:|:---:|:---:|:---:|
|     |     | 00  | 01  | 11  | 10  |
|  A  |  0  |  0  |  0  |  1  |  1  |
|     |  1  |  1  |  1  |  1  |  0  |

(A ⊕ B) ∨ (A ∧ C) ≡ ¬A ∧ B ∨ A ∧ ¬B ∨ A ∧ C
```

The grid is a *Karnaugh map*: the column's values rearranged so that
neighbouring cells differ in exactly one variable (which is why the columns run
`00 01 11 10` and skip the binary order). A rectangle of ones whose sides are
powers of two is one product term, and a bigger rectangle means a shorter term.
Here the two ones on the right of the top row are `¬A ∧ B`, the two on the left
of the bottom row are `A ∧ ¬B`, and the pair `01`, `11` in the bottom row is
`A ∧ C`. The last line joins them: a *minimal sum of products* for the column,
written as the head of a derivation.

Which invites one more step. The first two terms of that formula are the
exclusive-or pattern from lesson 8. Put the cursor on `¬A` in the formula line,
preview `:TruthTableXor`, and apply it as a step (`<leader>ttA`):

```text
(A ⊕ B) ∨ (A ∧ C) ≡ ¬A ∧ B ∨ A ∧ ¬B ∨ A ∧ C
                  ≡ (A ⊕ B) ∨ A ∧ C
```

That is the expression the column was built from, up to a pair of parentheses.

Rows can be missing, and that is useful. Suppose a door only ever reports
"open" when its key is present, so the state "no key, door open" never occurs.
Build the table, then delete that row and ask for the map:

key and door

```text
| key | door | key ∧ door |
|:---:|:----:|:----------:|
|  0  |  0   |     0      |
|  0  |  1   |     0      |
|  1  |  0   |     0      |
|  1  |  1   |     1      |
```

Put the cursor on the row where `key` is `0` and `door` is `1`, in the last
column. Run `:TruthTableDropRow` (`<leader>ttr`), then `:TruthTableKarnaugh`:

```text
| key | door | key ∧ door |
|:---:|:----:|:----------:|
|  0  |  0   |     0      |
|  1  |  0   |     0      |
|  1  |  1   |     1      |

Karnaugh map for key ∧ door:

|     |     | door |     |
|:---:|:---:|:----:|:---:|
|     |     |  0   |  1  |
| key |  0  |  0   |  X  |
|     |  1  |  0   |  1  |

key ∧ door ≡ door
```

The missing input shows as `X`, a *don't-care*: the minimiser may count it as a
one or a zero, whichever gives the shorter formula. Counting it as a one lets
the whole `door` column of the map form one group, so the condition shrinks to
a single variable. Here `key ∧ door ≡ door` holds for the allowed states,
under our assumption that an open door requires a key. On the omitted state
(`key = 0`, `door = 1`) the expressions differ, so this is an equivalence under
that assumption, rather than the unrestricted equivalence from lesson 4.

## 10. From code to logic and back

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
the three branches fires, which is the expression below. The repeated
`not C` is the thing to tidy. Put the cursor on either `not C`, preview
`:TruthTableFactor`, and apply it as a step; then, with the cursor on `S` in
the new line, commute and apply that as a step as well:

S or (A and not C) or (G and not C)

```text
S or (A and not C) or (G and not C)
≡ S ∨ (¬C ∧ (A ∨ G))
≡ (¬C ∧ (A ∨ G)) ∨ S
```

Read the last line back into code, one name per group:

```js
function canAccess({ isSuperAdmin, isAdmin, hasGrant, isClassified }) {
  const hasAdminOrGrant = isAdmin || hasGrant;
  const canAccessUnclassified = !isClassified && hasAdminOrGrant;
  return canAccessUnclassified || isSuperAdmin;
}
```

The derivation is the argument that the two functions agree. If you would
sooner see it than trust it, run `:.TruthTable` on a line holding both
expressions separated by `|` and compare the columns, as in lesson 4.

## Quick reference

| Command | Key | What it does |
|---|---|---|
| `:TruthTable {N or names or expressions}` | `<leader>ttn` | build a table; on a line, from that line |
| `:TruthTableExpand {expressions}` | `<leader>tte` | append computed columns |
| `:TruthTableToggle` | `<leader>ttt` | switch `0`/`1` and `F`/`T` |
| `:TruthTableDropRow` | `<leader>ttr` | remove the row under the cursor |
| `:TruthTableDropColumn` | `<leader>ttc` | remove the column under the cursor |
| `:TruthTableKarnaugh` | `<leader>ttk` | Karnaugh map and minimal formula for a column |
| `:TruthTableDeMorgan` | `<leader>ttd` | preview De Morgan at the cursor |
| `:TruthTableCommute[!]` | `<leader>tts`, `<leader>ttS` | preview swapping an operand with its neighbour |
| `:TruthTableDistribute` | `<leader>ttx` | preview distributing an operand into a group |
| `:TruthTableFactor` | `<leader>ttf` | preview factoring an operand out of its terms |
| `:TruthTableXor` | `<leader>tto` | preview recognising `⊕` or `⇔` |
| `:TruthTableApply` | `<leader>tta` | replace the expression with the preview |
| `:TruthTableApplyStep` | `<leader>ttA` | add the preview below as a `≡` step |

`:help truth-table` has the full reference, including the parts this course
skipped: escaping in headings, the rules for which columns a Karnaugh map reads
as inputs, and configuring the abbreviations.
