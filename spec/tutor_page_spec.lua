local page = require("truth-table.tutor_page")

local function slice(list, first, last)
    local out = {}
    for index = first, last do
        out[#out + 1] = list[index]
    end
    return out
end

describe("tutor_page.lines", function()
    it("splits a block string and drops the newlines that close it", function()
        assert.are.same({ "p q", "", "r" }, page.lines("p q\n\nr\n"))
        assert.are.same({ "p q" }, page.lines("p q"))
    end)

    it("keeps blank lines that open the block", function()
        assert.are.same({ "", "(marker)" }, page.lines("\n(marker)\n"))
    end)

    it("is empty for a missing or blank block", function()
        assert.are.same({}, page.lines(nil))
        assert.are.same({}, page.lines(""))
        assert.are.same({}, page.lines("\n"))
    end)
end)

describe("tutor_page.reflow", function()
    it("joins the lines of a paragraph and keeps paragraphs apart", function()
        assert.are.same(
            { "A proposition is a statement that is true or false.", "", "Logic names them." },
            page.reflow({ "A proposition is a statement", "that is true or false.", "", "Logic names them." })
        )
    end)

    it("joins a list item with its continuation, and starts a line per item", function()
        assert.are.same(
            { "Three:", "- `not p` is true when `p` is false.", "- `p or q` is the inclusive or: both count." },
            page.reflow({
                "Three:",
                "- `not p` is true when `p`",
                "  is false.",
                "- `p or q` is the inclusive",
                "  or: both count.",
            })
        )
    end)

    it("leaves fenced blocks, indented commands, table rows and headings as written", function()
        local lines = {
            "Run:",
            "",
            "    :TruthTableExpand a xor b",
            "",
            "```text",
            "|  a  |  b  |",
            "≡ ¬g ∧ ¬h",
            "```",
            "| Command | Key |",
            "|---|---|",
            "## Heading",
            "then prose",
            "goes on.",
        }
        local expected = slice(lines, 1, 11)
        expected[12] = "then prose goes on."
        assert.are.same(expected, page.reflow(lines))
    end)
end)

describe("tutor_page.render", function()
    local course = {
        { part = "Tables", title = "First", aim = "Find your way.", steps = { { text = "Read\nthis.\n" } } },
        {
            part = "Rewriting",
            title = "Second",
            aim = "Build a table.",
            steps = {
                { text = "Warm up.\n" },
                {
                    text = "Run it on\nthe line.\n",
                    template = "p q\n",
                    expect = "|  p  |  q  |\n|:---:|:---:|\n",
                    note = "Rows count\nupward.\n",
                },
            },
        },
    }

    it("heads a lesson's first step with the title and the aim", function()
        local lines = page.render(course, { lesson = 2, step = 1 })
        assert.are.same({
            "## 2. Second",
            "",
            "**Aim:** Build a table.",
            "",
            "Warm up.",
        }, slice(lines, 1, 5))
    end)

    it("heads a later step with the title alone", function()
        local lines = page.render(course, { lesson = 2, step = 2 })
        assert.are.same({ "## 2. Second", "", "Run it on the line." }, slice(lines, 1, 3))
    end)

    it("shows the expectation fenced, between the instructions and the remark", function()
        local lines = page.render(course, { lesson = 2, step = 2 })
        assert.are.same({
            "Run it on the line.",
            "",
            "You should see:",
            "",
            "```text",
            "|  p  |  q  |",
            "|:---:|:---:|",
            "```",
            "",
            "Rows count upward.",
            "",
            "---",
        }, slice(lines, 3, #lines))
    end)

    it("names the keys that move only in the first lesson", function()
        local keys = "\n---\n\n`]]` next step, `[[` previous step"
        local first = table.concat(page.render(course, { lesson = 1, step = 1 }), "\n")
        assert.are.equal(keys, first:sub(-#keys))
        local later = table.concat(page.render(course, { lesson = 2, step = 1 }), "\n")
        assert.are.equal("\n---", later:sub(-4))
    end)

    it("leaves the expectation out of a step that has only reading", function()
        local text = table.concat(page.render(course, { lesson = 1, step = 1 }), "\n")
        assert.is_nil(text:find("You should see", 1, true))
        assert.is_truthy(text:find("Read this.", 1, true))
    end)
end)

describe("tutor_page.body", function()
    local blue = "TruthTableTutorBlue"

    it("takes the markers out of a ```logic block and says which row each span is on", function()
        local lines, spans = page.body("Watch `a`:\n\n```logic\n[:blue a] ∨ (a ∧ b)  ≡  a\na ∧ [:blue (a ∨ b)]  ≡  a\n```\n")
        assert.are.same({ "Watch `a`:", "", "```logic", "a ∨ (a ∧ b)  ≡  a", "a ∧ (a ∨ b)  ≡  a", "```" }, lines)
        assert.are.same({
            { row = 4, col = 0, end_col = 1, group = blue },
            { row = 5, col = 6, end_col = 15, group = blue },
        }, spans)
    end)

    it("counts rows after reflow, so a span below a wrapped paragraph lands on its line", function()
        local lines, spans = page.body("A paragraph\nover two lines.\n\n```logic\n[:blue a]\n```\n")
        assert.are.same({ "A paragraph over two lines.", "", "```logic", "a", "```" }, lines)
        assert.are.same({ { row = 4, col = 0, end_col = 1, group = blue } }, spans)
    end)

    it("refuses a span in prose, and in a block that is not logic", function()
        local lines, err = page.body("Watch [:blue a] here.\n")
        assert.is_nil(lines)
        assert.are.equal("a colour span outside a ```logic block: Watch [:blue a] here.", err)
        lines, err = page.body("```text\n[:blue a]\n```\n")
        assert.is_nil(lines)
        assert.are.equal("a colour span outside a ```logic block: [:blue a]", err)
        lines, err = page.body("```lua\nx = y[:blue 1]\n```\n")
        assert.is_nil(lines)
        assert.are.equal("a colour span outside a ```logic block: x = y[:blue 1]", err)
    end)

    it("passes a marker error on with its line", function()
        local lines, err = page.body("```logic\na ∨ [:purple b]\n```\n")
        assert.is_nil(lines)
        assert.are.equal('unknown colour "purple" at byte 7: a ∨ [:purple b]', err)
    end)

    it("leaves a fenced block's own brackets alone", function()
        local lines, spans = page.body("```lua\nreturn range['end'][1]\n```\n")
        assert.are.same({ "```lua", "return range['end'][1]", "```" }, lines)
        assert.are.same({}, spans)
    end)
end)

describe("tutor_page.template", function()
    it("takes the markers out anywhere, keeping the rows", function()
        local lines, spans = page.template("[:yellow a] or (not a and b)\n\nx [:red and 1]\n")
        assert.are.same({ "a or (not a and b)", "", "x and 1" }, lines)
        assert.are.same({
            { row = 1, col = 0, end_col = 1, group = "TruthTableTutorYellow" },
            { row = 3, col = 2, end_col = 7, group = "TruthTableTutorRed" },
        }, spans)
    end)

    it("is empty, with no spans, for a missing template", function()
        local lines, spans = page.template(nil)
        assert.are.same({}, lines)
        assert.are.same({}, spans)
    end)

    it("passes a marker error on with its line", function()
        local lines, err = page.template("[:blue a\n")
        assert.is_nil(lines)
        assert.are.equal("no closing ] for the span at byte 1: [:blue a", err)
    end)
end)

describe("tutor_page.render with spans", function()
    local blue, red = "TruthTableTutorBlue", "TruthTableTutorRed"
    local course = {
        {
            part = "Spans",
            title = "Spans",
            aim = "See a part.",
            steps = {
                {
                    text = "Look:\n\n```logic\n[:blue a] ∨ b\n```\n",
                    template = "a or b\n",
                    expect = "| a |\n",
                    note = "And:\n\n```logic\na ∨ [:red b]\n```\n",
                    solution = {},
                },
                { text = "Plain.\n", expect = "[:blue x]\n", solution = {} },
            },
        },
    }

    it("offsets the rows past the header, and past the expectation for the note", function()
        local lines, spans = page.render(course, { lesson = 1, step = 1 })
        assert.are.equal("a ∨ b", lines[8])
        assert.are.equal("a ∨ b", lines[20])
        assert.are.same({
            { row = 8, col = 0, end_col = 1, group = blue },
            { row = 20, col = 6, end_col = 7, group = red },
        }, spans)
    end)

    it("refuses a span in the expectation, naming the field", function()
        local lines, err = page.render(course, { lesson = 1, step = 2 })
        assert.is_nil(lines)
        assert.are.equal("expect: a colour span in the expected result: [:blue x]", err)
    end)

    it("renders a step with no markers as before, with no spans", function()
        local plain = { { part = "P", title = "T", aim = "A.", steps = { { text = "Read.\n" } } } }
        local lines, spans = page.render(plain, { lesson = 1, step = 1 })
        assert.are.equal("Read.", lines[5])
        assert.are.same({}, spans)
    end)
end)

-- A lesson's part is the one the last lesson at or before it opened. The
-- bar has a cell per lesson, coloured by state: the lessons up to `furthest`
-- visited, the one shown current, the rest ahead.
describe("tutor_page.progress", function()
    local course = {
        { part = "Tables", title = "First", aim = "A.", steps = { { text = "Read.\n" } } },
        { title = "Between", aim = "B.", steps = { { text = "Read.\n" } } },
        { part = "Rewriting", title = "Third", aim = "C.", steps = { { text = "Read.\n" }, { text = "Read.\n" } } },
    }
    local visited, current, ahead = "%#TruthTableTutorVisited#", "%#TruthTableTutorCurrent#", "%#TruthTableTutorAhead#"

    it("is the bar by state, the lesson and step, and the part, in winbar format", function()
        assert.are.equal(
            current .. "█" .. ahead .. "██%* lesson 1 of 3, step 1 of 1 %<%=Part 1 of 2: Tables",
            page.progress(course, { lesson = 1, step = 1, furthest = 1 })
        )
        assert.are.equal(
            visited .. "█" .. current .. "█" .. visited .. "█%* lesson 2 of 3, step 1 of 1 %<%=Part 1 of 2: Tables",
            page.progress(course, { lesson = 2, step = 1, furthest = 3 })
        )
        assert.are.equal(
            visited .. "██" .. current .. "█%* lesson 3 of 3, step 2 of 2 %<%=Part 2 of 2: Rewriting",
            page.progress(course, { lesson = 3, step = 2, furthest = 3 })
        )
    end)

    it("doubles a % in a part's name, which the winbar would otherwise read", function()
        local odd = { { part = "100% logic", title = "T", aim = "A.", steps = { { text = "Read.\n" } } } }
        assert.are.equal(
            current .. "█%* lesson 1 of 1, step 1 of 1 %<%=Part 1 of 1: 100%% logic",
            page.progress(odd, { lesson = 1, step = 1, furthest = 1 })
        )
    end)

    it("names a highlight group per state, with a default link", function()
        for _, state in ipairs({ "visited", "current", "ahead" }) do
            assert.are.equal("string", type(page.STATES[state].group), state)
            assert.are.equal("string", type(page.STATES[state].link), state)
        end
    end)
end)

describe("tutor_page.check", function()
    it("is nil for a course whose markers are all right", function()
        local course = { { part = "P", title = "T", aim = "A.", steps = { { text = "```logic\n[:blue a]\n```\n", template = "[:red a]\n" } } } }
        assert.is_nil(page.check(course))
    end)

    it("refuses a course whose first lesson opens no part", function()
        local course = { { title = "T", aim = "A.", steps = { { text = "Fine.\n" } } } }
        assert.are.equal("lesson 1: no part", page.check(course))
    end)

    it("names the lesson, step and field of the first wrong marker", function()
        local course = {
            { part = "P", title = "T", aim = "A.", steps = { { text = "Fine.\n" } } },
            { title = "U", aim = "B.", steps = { { text = "Fine.\n" }, { text = "Fine.\n", template = "[:blue a\n" } } },
        }
        assert.are.equal("lesson 2 step 2: template: no closing ] for the span at byte 1: [:blue a", page.check(course))
        course[1].steps[1].note = "```logic\na [:purple b]\n```\n"
        assert.are.equal('lesson 1 step 1: note: unknown colour "purple" at byte 3: a [:purple b]', page.check(course))
    end)
end)
