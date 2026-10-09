local markdown = require("truth-table.markdown")
local core = require("truth-table.core")

describe("Markdown codec", function()
    it("round-trips labels containing pipes and backslashes", function()
        local tbl = { headers = { "p | q", "path\\name", "slash\\|pipe" }, rows = { { 0, 1, 0 } }, encoding = "tf" }
        local lines = assert(markdown.format(tbl))
        -- Fixed wire spelling prevents matching encoder/decoder bugs from
        -- making the round-trip assertion pass together.
        assert.are.equal("| p \\| q | path\\\\name | slash\\\\\\|pipe |", lines[1])
        assert.are.same(tbl, markdown.parse_table_lines(lines))
        local expanded = assert(core.expand(tbl, { "not :h1" }))
        assert.are.same(expanded, markdown.parse_table_lines(markdown.format(expanded)))
    end)

    it("does not count escaped pipes as cursor column boundaries", function()
        local line = "| p \\| q | B |"
        assert.are.equal(1, markdown.column_index(line, 7))
        assert.are.equal(2, markdown.column_index(line, 11))
        assert.are.same({ "p | q", "B" }, markdown.row(line))
    end)

    it("injects display width without changing global defaults", function()
        local lines = markdown.format({ headers = { "界" }, rows = { { 1 } }, encoding = "bits" }, function(s)
            return s == "界" and 4 or #s
        end)
        assert.are.same({ "| 界 |", "|:----:|", "|  1   |" }, lines)
        assert.are.equal(1, markdown.display_width("界"))
    end)

    it("refuses a heading that cannot head a column, whether read or written", function()
        assert.is_nil(markdown.parse_table_lines({ "| A | A |", "|---|---|", "| 0 | 1 |" }))
        assert.is_nil(markdown.parse_table_lines({ "| A |  |", "|---|---|", "| 0 | 1 |" }))
        assert.is_nil(markdown.replace_heading("| A | B |", 2, "A"))
        assert.is_nil(markdown.replace_heading("| A | B |", 2, "A\nB"))
        assert.is_nil(markdown.replace_heading("| A | B |", 3, "C"))
        assert.are.equal("| A | C |", markdown.replace_heading("| A | B |", 2, "C"))
    end)
end)

describe("Markdown syntax validation", function()
    it("rejects escaped closing delimiters rather than losing trailing text", function()
        local tbl, err = markdown.parse_table_lines({ "|A|", "|---|", "|1|discarded\\|" })
        assert.is_nil(tbl)
        assert.is_truthy(err:find("closing pipe", 1, true))
        assert.is_nil(markdown.parse_table_lines({ "|A|discarded\\|", "|---|", "|1|" }))
        local cells, row_err = markdown.row("|1|discarded\\|")
        assert.is_nil(cells)
        assert.are.equal("Expected an unescaped closing pipe", row_err)
        assert.are.same({ "A\\", "B" }, markdown.row("|A\\\\|B|"))
    end)
end)

describe("table discovery", function()
    it("isolates adjacent tables for cursors on headings, separators, or data", function()
        local lines = { "|A|", "|---|", "|0|", "|B|", "|---|", "|1|" }
        for row = 1, 6 do
            local bounds = assert(markdown.find_table(lines, row))
            assert.are.equal(row <= 3 and 1 or 4, bounds.start_line)
            assert.are.equal(row <= 3 and 3 or 6, bounds.end_line)
        end
    end)

    it("finds an empty table and ignores neighboring pipe prose", function()
        local lines = { "|prose|", "|A|", "|---|", "", "|unrelated|" }
        local bounds = assert(markdown.find_table(lines, 2))
        assert.are.equal(2, bounds.start_line)
        assert.are.equal(3, bounds.end_line)
        assert.is_nil(markdown.find_table(lines, 1))
        assert.is_nil(markdown.find_table(lines, 4))
        assert.is_nil(markdown.find_table(lines, 5))
    end)

    it("skips backtick and tilde fences with matching close markers", function()
        for _, fence in ipairs({ "```lua", "~~~~markdown", "  ```" }) do
            local marker = fence:match("[`~]+")
            local lines = { fence, "|A|", "|---|", "|0|", marker .. marker, "|B|", "|---|", "|1|" }
            assert.is_nil(markdown.find_table(lines, 3))
            assert.are.equal(6, assert(markdown.find_table(lines, 8)).start_line)
        end
    end)

    it("does not close fences with shorter or different markers or info text", function()
        for _, closing in ipairs({ "```", "~~~~", "````oops" }) do
            local lines = { "````lua", closing, "|A|", "|---|", "|0|" }
            assert.is_nil(markdown.find_table(lines, 5))
        end
    end)

    it("preserves supported indentation and excludes indented code", function()
        local bounds = assert(markdown.find_table({ "  |A|", "  |---|", "  |0|" }, 3))
        assert.are.equal("  ", bounds.indent)
        assert.is_nil(markdown.find_table({ "    |A|", "    |---|", "    |0|" }, 3))
        assert.is_nil(markdown.find_table({ "\t|A|", "\t|---|", "\t|0|" }, 3))
    end)

    it("includes malformed data in the range so validation can refuse the edit", function()
        local lines = { "|A|", "|---|", "|0|", "|invalid|extra|" }
        assert.are.equal(4, assert(markdown.find_table(lines, 3)).end_line)
        assert.is_nil(markdown.parse_table_lines(lines))
    end)

    it("maps multibyte cursor positions and delimiters consistently", function()
        local line = "| ¬A \\| B | C |"
        local pipe = assert(line:find("\\|", 1, true))
        assert.are.equal(1, markdown.column_index(line, pipe))
        local second = assert(line:find("| C", 1, true))
        assert.are.equal(2, markdown.column_index(line, second - 1))
        assert.are.equal(1, markdown.column_index(line, 0))
    end)
end)

describe("literal reference heading rendering", function()
    it("escapes backticks so displayed labels retain their reference syntax", function()
        local tbl = { headers = { "¬`A`", "p | `q`" }, rows = { { 0, 1 } }, encoding = "bits" }
        local lines = assert(markdown.format(tbl))
        assert.are.equal("| ¬\\`A\\` | p \\| \\`q\\` |", lines[1])
        assert.are.same(tbl, markdown.parse_table_lines(lines))
        assert.are.same({ "¬`A`", "p | `q`" }, markdown.row(lines[1]))
    end)
end)

describe("markdown.heading_cell", function()
    it("gives the bytes of a cell's content without its padding", function()
        local line = "  |  A  | ¬A ∧ B |   |"
        local first, last = markdown.heading_cell(line, 1)
        assert.are.equal("A", line:sub(first, last))
        first, last = markdown.heading_cell(line, 2)
        assert.are.equal("¬A ∧ B", line:sub(first, last))
    end)

    it("is nil for a blank cell or a column the line lacks", function()
        local line = "| A |   |"
        assert.is_nil(markdown.heading_cell(line, 2))
        assert.is_nil(markdown.heading_cell(line, 3))
    end)

    it("does not split a cell at an escaped pipe", function()
        local line = "| p \\| q | C |"
        local first, last = markdown.heading_cell(line, 1)
        assert.are.equal("p \\| q", line:sub(first, last))
    end)
end)

describe("markdown.display_width (pure default)", function()
    it("counts ASCII as one column each", function()
        assert.are.equal(3, markdown.display_width("abc"))
        assert.are.equal(0, markdown.display_width(""))
    end)

    it("counts a multibyte codepoint as one column", function()
        -- The logic symbols are 3 UTF-8 bytes but one display column.
        assert.are.equal(1, markdown.display_width("∧"))
        assert.are.equal(5, markdown.display_width("A ∧ B"))
    end)
end)

describe("markdown.center_pad", function()
    it("centers within the width", function()
        assert.are.equal(" x ", markdown.center_pad("x", 3))
        assert.are.equal("ab", markdown.center_pad("ab", 2))
    end)

    it("biases the extra space to the right on odd padding", function()
        assert.are.equal("x ", markdown.center_pad("x", 2))
    end)

    it("measures with the function it is given", function()
        assert.are.equal(
            " 界 ",
            markdown.center_pad("界", 4, function()
                return 2
            end)
        )
    end)
end)

describe("table-line recognition", function()
    it("recognizes table and separator lines", function()
        assert.is_true(markdown.is_table_line("| A | B |"))
        assert.is_true(markdown.is_table_line("  |x|  "))
        assert.is_false(markdown.is_table_line("not a table"))
    end)

    it("recognizes separator rows with optional colons", function()
        assert.is_true(markdown.is_separator("|:---:|:---:|"))
        assert.is_true(markdown.is_separator("| --- | --- |"))
        assert.is_false(markdown.is_separator("| A | B |"))
    end)

    it("splits a row into trimmed cells", function()
        assert.are.same({ "A", "B", "C" }, markdown.row("|  A | B  |  C |"))
    end)
end)
