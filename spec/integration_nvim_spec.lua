-- The commands and default keymaps end to end, through the plugin entry
-- point and with which-key unavailable. Each case writes the buffer it needs.
-- Runs inside Neovim (make test-nvim): busted with nlua as its interpreter.
vim.opt.rtp:append(vim.fn.getcwd())
package.preload["which-key"] = function() error("which-key intentionally absent") end
vim.cmd("runtime plugin/truth-table.lua")

local core = require("truth-table.core")

local notified
vim.notify = function(message)
    notified = message
end

local function buffer()
    return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

local function set(lines, row, col)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, { row or 1, col or 0 })
    notified = nil
end

describe("the plugin entry point", function()
    it("loads once, and can be sourced and set up again", function()
        assert.is_truthy(vim.g.loaded_truth_table)
        vim.cmd("runtime plugin/truth-table.lua")
        require("truth-table").setup()
        require("truth-table").setup()
    end)

    it("defines every command", function()
        local commands = vim.api.nvim_get_commands({})
        for _, command in ipairs({
            "TruthTable", "TruthTableExpand", "TruthTableToggle", "TruthTableDropRow", "TruthTableDropColumn",
            "TruthTableKarnaugh", "TruthTableDeMorgan", "TruthTableDeMorganApply", "TruthTableFactor",
            "TruthTableDistribute", "TruthTableCommute", "TruthTableApply", "TruthTableApplyStep", "TruthTableXor",
            "TruthTableSimplify", "TruthTableTutor",
        }) do
            assert.is_truthy(commands[command], command)
        end
    end)

    it("maps the default keys to their commands", function()
        for key, command in pairs({
            t = "TruthTableToggle", f = "TruthTableFactor", x = "TruthTableDistribute", s = "TruthTableCommute",
            S = "TruthTableCommute!", a = "TruthTableApply", A = "TruthTableApplyStep", d = "TruthTableDeMorgan",
            o = "TruthTableXor", z = "TruthTableSimplify",
        }) do
            assert.are.equal("<Cmd>" .. command .. "<CR>", vim.fn.maparg("<leader>tt" .. key, "n"), key)
        end
    end)

    -- A key-sorted popup still shows which keys belong together.
    it("opens each key's description with its family", function()
        for key, family in pairs({
            n = "Table", e = "Table", k = "Table", d = "Rewrite", f = "Rewrite", z = "Rewrite", a = "Apply", A = "Apply",
        }) do
            local description = vim.fn.maparg("<leader>tt" .. key, "n", false, true).desc
            assert.is_truthy(description:find("^" .. family .. ": "), key .. ": " .. description)
        end
    end)
end)

describe("the table commands", function()
    it("build a table, toggle it and expand it", function()
        set({ "" })
        vim.cmd("TruthTable A B")
        vim.api.nvim_win_set_cursor(0, { 3, 3 })
        vim.cmd("TruthTableToggle")
        vim.cmd("TruthTableExpand not A, A iff B")
        local tbl = assert(core.parse_table_lines(vim.api.nvim_buf_get_lines(0, 0, 6, false)))
        assert.are.equal("T", tbl.rows[1][3])
        assert.are.equal("F", tbl.rows[2][4])
    end)

    it("leave a row with too many cells as it is, and say so", function()
        set({ "|A|B|", "|---|---|", "|1|0|1|" }, 3, 1)
        local before = buffer()
        vim.cmd("TruthTableToggle")
        assert.is_truthy(notified)
        assert.are.same(before, buffer())
    end)

    it("expand from a column reference, drop a column and a row, and toggle what is left", function()
        set({ "| B | A ∧ B |", "|---|---|", "|0|0|", "|1|1|" }, 3, 3)
        vim.cmd("TruthTableExpand not :h2")
        local referenced = assert(core.parse_table_lines(buffer()))
        assert.are.equal("1", referenced.rows[1][3])
        assert.are.equal("0", referenced.rows[2][3])

        vim.api.nvim_win_set_cursor(0, { 3, 2 })
        vim.cmd("TruthTableDropColumn")
        vim.cmd("TruthTableDropRow")
        local edited = assert(core.parse_table_lines(buffer()))
        assert.are.equal(2, #edited.headers)
        assert.are.equal(1, #edited.rows)
        assert.are.equal("A ∧ B", edited.headers[1])
        assert.are.equal("1", edited.rows[1][1])

        vim.cmd("TruthTableToggle")
        assert.are.equal("T", assert(core.parse_table_lines(buffer())).rows[1][1])
    end)

    it("drop the column of a heading that holds an escaped pipe", function()
        set(assert(core.format_table({ "p | q", "B" }, { { "0", "1" } })))
        local q = assert(buffer()[1]:find("q", 1, true))
        vim.api.nvim_win_set_cursor(0, { 1, q - 1 })
        vim.cmd("TruthTableDropColumn")
        local edited = assert(core.parse_table_lines(buffer()))
        assert.are.equal("B", edited.headers[1])
        assert.are.equal("1", edited.rows[1][1])
    end)

    -- The string-cell functions are compatibility adapters for callers of
    -- core; a command that reached for one would raise here.
    it("go through the semantic operations, and edit nothing on an error", function()
        local legacy = {}
        for _, name in ipairs({
            "build_truth_table", "expand", "toggle_table", "drop_row", "drop_column", "parse_table_lines", "format_table",
        }) do
            legacy[name] = core[name]
            core[name] = function() error("legacy adapter used by command: " .. name) end
        end
        finally(function()
            for name, fn in pairs(legacy) do
                core[name] = fn
            end
        end)

        set({ "A and B", "not A" })
        vim.cmd("1,2TruthTable")
        vim.api.nvim_win_set_cursor(0, { 3, 3 })
        vim.cmd("TruthTableToggle")
        vim.cmd("TruthTableExpand A iff B")
        vim.cmd("TruthTableDropColumn")
        vim.cmd("TruthTableDropRow")
        local semantic = assert(core.parse_model(buffer()))
        assert.are.equal("tf", semantic.encoding)
        assert.are.equal(3, #semantic.rows)
        assert.are.equal(4, #semantic.headers)

        local before = buffer()
        vim.cmd("TruthTableExpand missing")
        assert.are.same(before, buffer())
    end)

    it("leave a row whose closing pipe is escaped as it is, and say so", function()
        set({ "|A|", "|---|", "|1|discarded\\|" }, 3, 1)
        local before = buffer()
        vim.cmd("TruthTableToggle")
        assert.is_truthy(notified)
        assert.are.same(before, buffer())
    end)

    it("toggle the table under the cursor and leave the one above it", function()
        set({ "|A|", "|---|", "|0|", "  |B|", "  |---|", "  |1|" }, 6, 4)
        vim.cmd("TruthTableToggle")
        local adjacent = buffer()
        assert.are.same({ "|A|", "|---|", "|0|" }, { adjacent[1], adjacent[2], adjacent[3] })
        assert.are.equal("  ", adjacent[4]:sub(1, 2))
        assert.is_truthy(adjacent[6]:find("T", 1, true), adjacent[6])
    end)

    it("read a table in a fence or an indented block as code", function()
        for _, code_lines in ipairs({
            { "```markdown", "|A|", "|---|", "|0|", "```" },
            { "    |A|", "    |---|", "    |0|" },
        }) do
            set(code_lines, 3, 1)
            vim.cmd("TruthTableToggle")
            assert.is_truthy(notified, code_lines[1])
            assert.are.same(code_lines, buffer())
        end
    end)

    it("report a parse error with the byte it is at, and edit nothing", function()
        set({ "|A|", "|---|", "|0|" }, 3, 1)
        local before = buffer()
        vim.cmd("TruthTableExpand A ∧ )")
        assert.is_truthy(notified and notified:find("at byte 7", 1, true), notified)
        assert.are.same(before, buffer())
    end)

    it("expand from a column an earlier expansion added", function()
        set({ "|A|", "|---|", "|0|", "|1|" }, 3, 1)
        vim.cmd("TruthTableExpand not :h1")
        vim.cmd("TruthTableExpand not :h2")
        local chained = assert(core.parse_model(buffer()))
        assert.are.equal(0, chained.rows[1][3])
        assert.are.equal(1, chained.rows[2][3])
    end)
end)

-- In normal mode the current line is the argument, unless it is blank.
describe("<leader>ttn", function()
    it("prefills the command on a blank line", function()
        local ttn = assert(vim.fn.maparg("<leader>ttn", "n", false, true).callback)
        set({ "A and B", "" }, 2, 0)
        assert.are.equal(":TruthTable ", ttn())
    end)

    it("builds the table from the current line, in its place", function()
        set({ "A and B", "" }, 1, 0)
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<leader>ttn", true, false, true), "x", false)
        local from_line = assert(core.parse_model(vim.api.nvim_buf_get_lines(0, 0, 6, false)))
        assert.are.equal(3, #from_line.headers)
        assert.are.equal("A ∧ B", from_line.headers[3])
        assert.are.equal(4, #from_line.rows)
        assert.are.equal("", vim.api.nvim_buf_get_lines(0, 6, 7, false)[1])
    end)
end)

describe(":TruthTableKarnaugh", function()
    local table_lines = {
        "  | A | B | A ∧ B |", "  |---|---|---|", "  |0|0|0|", "  |0|1|0|", "  |1|0|0|", "  |1|1|1|", "after",
    }

    -- The cursor column is the target.
    it("inserts the map and the formula below the table, at its indentation, and leaves the table alone", function()
        set(table_lines, 1, 14)
        vim.cmd("TruthTableKarnaugh")
        local lines = buffer()
        assert.are.equal("  |1|1|1|", lines[6])
        assert.are.equal("", lines[7])
        assert.are.equal("  Karnaugh map for A ∧ B:", lines[8])
        assert.is_truthy(lines[10]:match("^  |"), lines[10])
        assert.is_truthy(lines[14]:find("|  1  |  0  |  1  |", 1, true), lines[14])
        assert.are.equal("  A ∧ B ≡ A ∧ B", lines[16])
        assert.are.equal("after", lines[17])
    end)

    it("reports a column that the columns before it do not determine, and inserts nothing", function()
        set(table_lines, 3, 5)
        vim.cmd("TruthTableKarnaugh")
        assert.is_truthy(notified)
        assert.are.same(table_lines, buffer())
    end)
end)
