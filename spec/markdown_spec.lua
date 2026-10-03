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
        local headers, rows = core.expand({ headers = tbl.headers, rows = { { "F", "T", "F" } } }, { "not :h1" })
        local reparsed = assert(core.parse_table_lines(assert(core.format_table(headers, rows))))
        assert.are.same(headers, reparsed.headers)
        assert.are.same({ { "F", "T", "F", "T" } }, reparsed.rows)
    end)

    it("does not count escaped pipes as cursor column boundaries", function()
        local line = "| p \\| q | B |"
        assert.are.equal(1, markdown.column_index(line, 7))
        assert.are.equal(2, markdown.column_index(line, 11))
        assert.are.same({ "p | q", "B" }, markdown.split_row(line))
    end)

    it("injects display width without changing global defaults", function()
        local lines = assert(markdown.format({ headers = { "界" }, rows = { { 1 } } }, function(s)
            return s == "界" and 4 or #s
        end))
        assert.are.same({ "| 界 |", "|:----:|", "|  1   |" }, lines)
        assert.are.equal(1, markdown.display_width("界"))
    end)

    it("returns errors instead of crashing or emitting malformed tables", function()
        for _, tbl in ipairs({
            { headers = { "A" }, rows = { { "0", "1" } } },
            { headers = { "A" }, rows = { { "invalid" } } },
            { headers = { "A\nB" }, rows = {} },
            { headers = { " A" }, rows = {} },
            { headers = { 1 }, rows = {} },
        }) do
            local lines, err = markdown.format(tbl)
            assert.is_nil(lines)
            assert.is_string(err)
        end
        local lines, err = core.format_table({ "A" }, { { "0", "1" } })
        assert.is_nil(lines)
        assert.is_string(err)
    end)
end)

describe("Markdown syntax validation", function()
    it("rejects escaped closing delimiters rather than losing trailing text", function()
        local tbl, err = markdown.parse_table_lines({ "|A|", "|---|", "|1|discarded\\|" })
        assert.is_nil(tbl)
        assert.is_truthy(err:find("closing pipe", 1, true))
        assert.is_nil(markdown.parse_table_lines({ "|A|discarded\\|", "|---|", "|1|" }))
        assert.are.same({}, markdown.split_row("|1|discarded\\|"))
        assert.are.same({ "A\\", "B" }, markdown.split_row("|A\\\\|B|"))
    end)
end)

describe("table discovery", function()
    it("isolates adjacent tables for cursors on headings, separators, or data", function()
        local lines = { '|A|', '|---|', '|0|', '|B|', '|---|', '|1|' }
        for row = 1, 6 do
            local bounds = assert(markdown.find_table(lines, row))
            assert.are.equal(row <= 3 and 1 or 4, bounds.start_line)
            assert.are.equal(row <= 3 and 3 or 6, bounds.end_line)
        end
    end)

    it("finds an empty table and ignores neighboring pipe prose", function()
        local lines = { '|prose|', '|A|', '|---|', '', '|unrelated|' }
        local bounds = assert(markdown.find_table(lines, 2))
        assert.are.equal(2, bounds.start_line)
        assert.are.equal(3, bounds.end_line)
        assert.is_nil(markdown.find_table(lines, 1))
        assert.is_nil(markdown.find_table(lines, 4))
        assert.is_nil(markdown.find_table(lines, 5))
    end)

    it("skips backtick and tilde fences with matching close markers", function()
        for _, fence in ipairs({ '```lua', '~~~~markdown', '  ```' }) do
            local marker = fence:match('[`~]+')
            local lines = { fence, '|A|', '|---|', '|0|', marker .. marker, '|B|', '|---|', '|1|' }
            assert.is_nil(markdown.find_table(lines, 3))
            assert.are.equal(6, assert(markdown.find_table(lines, 8)).start_line)
        end
    end)

    it("does not close fences with shorter or different markers or info text", function()
        for _, closing in ipairs({ '```', '~~~~', '````oops' }) do
            local lines = { '````lua', closing, '|A|', '|---|', '|0|' }
            assert.is_nil(markdown.find_table(lines, 5))
        end
    end)

    it("preserves supported indentation and excludes indented code", function()
        local bounds = assert(markdown.find_table({ '  |A|', '  |---|', '  |0|' }, 3))
        assert.are.equal('  ', bounds.indent)
        assert.is_nil(markdown.find_table({ '    |A|', '    |---|', '    |0|' }, 3))
        assert.is_nil(markdown.find_table({ '\t|A|', '\t|---|', '\t|0|' }, 3))
    end)

    it("includes malformed data in the range so validation can refuse the edit", function()
        local lines = { '|A|', '|---|', '|0|', '|invalid|extra|' }
        assert.are.equal(4, assert(markdown.find_table(lines, 3)).end_line)
        assert.is_nil(markdown.parse_table_lines(lines))
    end)

    it("maps multibyte cursor positions and delimiters consistently", function()
        local line = '| ¬A \\| B | C |'
        local pipe = assert(line:find('\\|', 1, true))
        assert.are.equal(1, markdown.column_index(line, pipe))
        local second = assert(line:find('| C', 1, true))
        assert.are.equal(2, markdown.column_index(line, second - 1))
        assert.are.equal(1, markdown.column_index(line, 0))
    end)
end)

describe("literal reference heading rendering", function()
    it("escapes backticks so displayed labels retain their reference syntax", function()
        local tbl = { headers = { '¬`A`', 'p | `q`' }, rows = { { 0, 1 } }, encoding = 'bits' }
        local lines = assert(markdown.format(tbl))
        assert.are.equal('| ¬\\`A\\` | p \\| \\`q\\` |', lines[1])
        assert.are.same(tbl, markdown.parse_table_lines(lines))
        assert.are.same({ '¬`A`', 'p | `q`' }, markdown.split_row(lines[1]))
    end)
end)
