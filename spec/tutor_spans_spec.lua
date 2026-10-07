-- Unit tests for truth-table.tutor_spans: the `[:colour ...]` markers in
-- lesson text, stripped to byte spans, and the placing of those spans on the
-- lines vellum renders. Pure Lua, runs under busted.
local spans = require("truth-table.tutor_spans")

local function span(col, end_col, group)
    return { col = col, end_col = end_col, group = group }
end

describe("tutor_spans.strip", function()
    it("takes the markers out and keeps the bytes they marked", function()
        local clean, found = spans.strip("[:blue A] ∨ ¬(B ∧ ¬C)")
        assert.are.equal("A ∨ ¬(B ∧ ¬C)", clean)
        assert.are.same({ span(0, 1, "TruthTableTutorBlue") }, found)
    end)

    it("marks bytes, not syntax: a span may stop inside a group, after multibyte symbols", function()
        local clean, found = spans.strip("A ∨ [:red ¬(B] ∧ ¬C)")
        assert.are.equal("A ∨ ¬(B ∧ ¬C)", clean)
        -- A, space, ∨ (3 bytes), space; then ¬ (2 bytes), (, B.
        assert.are.same({ span(6, 10, "TruthTableTutorRed") }, found)
        assert.are.equal("¬(B", clean:sub(7, 10))
    end)

    it("reads every colour of the palette, and two spans on one line in order", function()
        local clean, found = spans.strip("[:green a] ∧ [:yellow b]")
        assert.are.equal("a ∧ b", clean)
        assert.are.same({ span(0, 1, "TruthTableTutorGreen"), span(6, 7, "TruthTableTutorYellow") }, found)
    end)

    it("spans the whole line, or its start, or its end", function()
        assert.are.same({ span(0, 7, "TruthTableTutorBlue") }, select(2, spans.strip("[:blue a ∧ b]")))
        assert.are.same({ span(0, 1, "TruthTableTutorBlue") }, select(2, spans.strip("[:blue a] ∧ b")))
        assert.are.same({ span(6, 7, "TruthTableTutorBlue") }, select(2, spans.strip("a ∧ [:blue b]")))
    end)

    it("pairs brackets inside a span, so Lua indexing can be marked", function()
        local clean, found = spans.strip("[:blue result[1]] or x")
        assert.are.equal("result[1] or x", clean)
        assert.are.same({ span(0, 9, "TruthTableTutorBlue") }, found)
        clean, found = spans.strip("¬[:green (prev:match '[%w_]' ∨ A)]")
        assert.are.equal("¬(prev:match '[%w_]' ∨ A)", clean)
        assert.are.same({ span(2, #clean, "TruthTableTutorGreen") }, found)
    end)

    it("leaves a bare bracket, the tutor's keys and `[:` with no word as text", function()
        for _, line in ipairs({ "range['end']", "`]]` next, `[[` previous", "a [:] b", "a [: x] b", "[", "]" }) do
            local clean, found = spans.strip(line)
            assert.are.equal(line, clean)
            assert.are.same({}, found)
        end
    end)

    it("leaves a line with no markers as it is, with no spans", function()
        local clean, found = spans.strip("a ∨ (a ∧ b)  ≡  a")
        assert.are.equal("a ∨ (a ∧ b)  ≡  a", clean)
        assert.are.same({}, found)
    end)

    it("refuses a colour it does not have, naming the byte", function()
        local clean, err = spans.strip("a ∨ [:purple b]")
        assert.is_nil(clean)
        assert.are.equal('unknown colour "purple" at byte 7', err)
    end)

    it("wants exactly one space after the colour", function()
        local _, err = spans.strip("[:blue]")
        assert.are.equal("a colour name must be followed by one space at byte 1", err)
        _, err = spans.strip("a [:blue  b]")
        assert.are.equal("a colour name must be followed by one space at byte 3", err)
    end)

    it("refuses a span inside a span", function()
        local _, err = spans.strip("[:blue a ∨ [:red b]]")
        assert.are.equal("a span inside a span at byte 14", err)
    end)

    it("refuses a span that never closes, naming where it opened", function()
        local _, err = spans.strip("a ∧ [:blue b")
        assert.are.equal("no closing ] for the span at byte 7", err)
        _, err = spans.strip("[:blue result[1]")
        assert.are.equal("no closing ] for the span at byte 1", err)
    end)

    it("refuses an empty span", function()
        local _, err = spans.strip("a [:blue ] b")
        assert.are.equal("an empty span at byte 3", err)
    end)
end)

describe("tutor_spans.place", function()
    local blue = "TruthTableTutorBlue"

    local function mark(row, col, end_col)
        return { row = row, col = col, end_col = end_col, group = blue, priority = 200 }
    end

    -- A code panel as vellum draws it: a label row, the lines with a margin
    -- of two and a prefix of two, padded, then a blank row.
    local markdown = { "```logic", "a ∨ b", "c", "```" }
    local lines = { "", "  logic", "    a ∨ b    ", "    c        ", "  " }
    local blocks = { { 0, 4, 1, 4 } }

    it("finds each line inside its block, offset by the spaces before it", function()
        local found = spans.place({
            { row = 2, col = 0, end_col = 1, group = blue },
            { row = 2, col = 6, end_col = 7, group = blue },
            { row = 3, col = 0, end_col = 1, group = blue },
        }, markdown, lines, blocks)
        assert.are.same({ mark(2, 4, 5), mark(2, 10, 11), mark(3, 4, 5) }, found)
    end)

    it("does not take a longer line that merely contains the clean one", function()
        local page = { "```logic", "a", "a ∨ b", "```" }
        local rendered = { "", "  logic", "    a ∨ b    ", "    a        ", "  " }
        local found = spans.place({ { row = 2, col = 0, end_col = 1, group = blue } }, page, rendered, blocks)
        assert.are.same({ mark(3, 4, 5) }, found)
    end)

    it("takes lines that read the same in order", function()
        local page = { "```logic", "a", "a", "```" }
        local rendered = { "", "  logic", "    a    ", "    a    ", "  " }
        local found = spans.place({
            { row = 2, col = 0, end_col = 1, group = blue },
            { row = 3, col = 0, end_col = 1, group = blue },
        }, page, rendered, blocks)
        assert.are.same({ mark(2, 4, 5), mark(3, 4, 5) }, found)
    end)

    it("keeps a line's leading spaces, and finds the line by all of them", function()
        local page = { "```logic", "a", "  ∧ b", "```" }
        local rendered = { "", "  logic", "    a    ", "      ∧ b    ", "  " }
        local found = spans.place({ { row = 3, col = 4, end_col = 5, group = blue } }, page, rendered, blocks)
        assert.are.same({ mark(3, 8, 9) }, found)
    end)

    it("gives a line it cannot find no marks: one vellum had to wrap, or one with no block", function()
        local page = { "```logic", "a ∨ b ∨ c", "```", "", "prose with x" }
        local rendered = { "", "  logic", "    a ∨ b", "    ∨ c", "  ", "", "  prose with x" }
        local found = spans.place({
            { row = 2, col = 0, end_col = 1, group = blue },
            { row = 5, col = 11, end_col = 12, group = blue },
        }, page, rendered, { { 0, 3, 1, 4 } })
        assert.are.same({}, found)
    end)

    it("searches the right block when two hold the same line", function()
        local page = { "```logic", "a", "```", "", "```text", "a", "```" }
        local rendered = { "", "  logic", "    a    ", "  ", "", "  text", "    a    ", "  " }
        local found = spans.place(
            { { row = 6, col = 0, end_col = 1, group = blue } },
            page, rendered, { { 0, 3, 1, 3 }, { 4, 3, 5, 3 } }
        )
        assert.are.same({ mark(6, 4, 5) }, found)
    end)

    it("marks nothing for no spans", function()
        assert.are.same({}, spans.place({}, markdown, lines, blocks))
    end)
end)
