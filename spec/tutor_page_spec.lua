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
        { title = "First", aim = "Find your way.", steps = { { text = "Read\nthis.\n" } } },
        {
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

    it("heads the pane with the lesson, the reader's place, and the aim", function()
        local lines = page.render(course, 2, 2)
        assert.are.same({
            "# 2. Second",
            "",
            "Lesson 2 of 2, step 2 of 2",
            "",
            "**Aim:** Build a table.",
            "",
            "Run it on the line.",
        }, slice(lines, 1, 7))
    end)

    it("shows the expectation fenced, between the instructions and the remark", function()
        local lines = page.render(course, 2, 2)
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
            "",
            "`]]` next step, `[[` previous step",
        }, slice(lines, 7, #lines))
    end)

    it("leaves the expectation out of a step that has only reading", function()
        local text = table.concat(page.render(course, 1, 1), "\n")
        assert.is_nil(text:find("You should see", 1, true))
        assert.is_truthy(text:find("Read this.", 1, true))
    end)
end)
