local markdown = require("truth-table.markdown")
local core = require("truth-table.core")

describe("Markdown codec", function()
    it("round-trips labels containing pipes and backslashes", function()
        local tbl = { headers = { "p | q", "path\\name", "slash\\|pipe" }, rows = { { 0, 1, 0 } }, encoding = "tf" }
        local lines = assert(markdown.format(tbl))
        assert.are.same(tbl, markdown.parse_table_lines(lines))
        local headers, rows = core.expand({ headers = tbl.headers, rows = { { "F", "T", "F" } } }, { "not `p | q`" })
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
        local calls = 0
        local lines = assert(markdown.format({ headers = { "界" }, rows = { { 1 } } }, function(s)
            calls = calls + 1
            return s == "界" and 4 or #s
        end))
        assert.are.equal("|:----:|", lines[2])
        assert.is_true(calls > 0)
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
