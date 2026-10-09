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
            "TruthTableSimplify", "TruthTableRewrites", "TruthTableTutor",
        }) do
            assert.is_truthy(commands[command], command)
        end
    end)

    it("maps the table family under <leader>T", function()
        for key, command in pairs({
            t = "TruthTableToggle", k = "TruthTableKarnaugh", r = "TruthTableDropRow", c = "TruthTableDropColumn",
        }) do
            assert.are.equal("<Cmd>" .. command .. "<CR>", vim.fn.maparg("<leader>T" .. key, "n"), key)
        end
    end)

    it("maps the rewrite family under <leader>l", function()
        for key, command in pairs({
            d = "TruthTableDeMorgan", f = "TruthTableFactor", x = "TruthTableDistribute",
            s = "TruthTableCommute", S = "TruthTableCommute!", o = "TruthTableXor", u = "TruthTableUnfold",
            m = "TruthTableDNF", M = "TruthTableCNF", z = "TruthTableSimplify", l = "TruthTableRewrites",
            v = "TruthTableVerify", V = "TruthTableVerify!",
            a = "TruthTableApply", A = "TruthTableApplyStep",
        }) do
            assert.are.equal("<Cmd>" .. command .. "<CR>", vim.fn.maparg("<leader>l" .. key, "n"), key)
        end
    end)

    -- Without which-key every mapping describes itself; with it, the gated
    -- leaves hide behind which_key_ignore and the popup labels them instead.
    it("describes every key", function()
        for lhs, want in pairs({
            ["<leader>Tn"] = "New table", ["<leader>Te"] = "Expand with columns", ["<leader>Tr"] = "Drop row",
            ["<leader>ld"] = "De Morgan", ["<leader>lm"] = "Disjunctive normal form",
            ["<leader>la"] = "Apply in place", ["<leader>lA"] = "Apply as a ≡ step",
        }) do
            local description = vim.fn.maparg(lhs, "n", false, true).desc
            assert.are.equal(want, description, lhs)
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
        local tbl = assert(core.parse(vim.api.nvim_buf_get_lines(0, 0, 6, false)))
        assert.are.equal("tf", tbl.encoding)
        assert.are.equal(1, tbl.rows[1][3])
        assert.are.equal(0, tbl.rows[2][4])
    end)

    it("leave a row with too many cells as it is, and say so", function()
        set({ "|A|B|", "|---|---|", "|1|0|1|" }, 3, 1)
        local before = buffer()
        vim.cmd("TruthTableToggle")
        assert.are.equal("Row 1: expected 2 cells, got 3", notified)
        assert.are.same(before, buffer())
    end)

    it("expand from a column reference, drop a column and a row, and toggle what is left", function()
        set({ "| B | A ∧ B |", "|---|---|", "|0|0|", "|1|1|" }, 3, 3)
        vim.cmd("TruthTableExpand not :h2")
        local referenced = assert(core.parse(buffer()))
        assert.are.equal(1, referenced.rows[1][3])
        assert.are.equal(0, referenced.rows[2][3])

        vim.api.nvim_win_set_cursor(0, { 3, 2 })
        vim.cmd("TruthTableDropColumn")
        vim.cmd("TruthTableDropRow")
        local edited = assert(core.parse(buffer()))
        assert.are.equal(2, #edited.headers)
        assert.are.equal(1, #edited.rows)
        assert.are.equal("A ∧ B", edited.headers[1])
        assert.are.equal(1, edited.rows[1][1])

        vim.cmd("TruthTableToggle")
        local toggled = assert(core.parse(buffer()))
        assert.are.equal("tf", toggled.encoding)
        assert.are.equal(1, toggled.rows[1][1])
    end)

    it("drop a row, then the next with .", function()
        set(core.format({ headers = { "p", "q" }, rows = { { 0, 0 }, { 0, 1 }, { 1, 0 } }, encoding = "bits" }), 3, 2)
        vim.cmd("TruthTableDropRow")
        vim.cmd("normal! .")
        local edited = assert(core.parse(buffer()))
        assert.are.same({ { 1, 0 } }, edited.rows)
    end)

    it("drop a column, then the one that took its place with .", function()
        set(core.format({ headers = { "p", "q", "r" }, rows = { { 0, 1, 0 } }, encoding = "bits" }))
        local q = assert(buffer()[1]:find("q", 1, true))
        vim.api.nvim_win_set_cursor(0, { 1, q - 1 })
        vim.cmd("TruthTableDropColumn")
        vim.cmd("normal! .")
        local edited = assert(core.parse(buffer()))
        assert.are.same({ "p" }, edited.headers)
        assert.are.same({ { 0 } }, edited.rows)
    end)

    it("drop the column of a heading that holds an escaped pipe", function()
        set(core.format({ headers = { "p | q", "B" }, rows = { { 0, 1 } }, encoding = "bits" }))
        local q = assert(buffer()[1]:find("q", 1, true))
        vim.api.nvim_win_set_cursor(0, { 1, q - 1 })
        vim.cmd("TruthTableDropColumn")
        local edited = assert(core.parse(buffer()))
        assert.are.equal("B", edited.headers[1])
        assert.are.equal(1, edited.rows[1][1])
    end)

    it("compose a whole session, and edit nothing on an error", function()
        set({ "A and B", "not A" })
        vim.cmd("1,2TruthTable")
        vim.api.nvim_win_set_cursor(0, { 3, 3 })
        vim.cmd("TruthTableToggle")
        vim.cmd("TruthTableExpand A iff B")
        vim.cmd("TruthTableDropColumn")
        vim.cmd("TruthTableDropRow")
        local semantic = assert(core.parse(buffer()))
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
        assert.are.equal("Line 3: Expected an unescaped closing pipe", notified)
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
        local chained = assert(core.parse(buffer()))
        assert.are.equal(0, chained.rows[1][3])
        assert.are.equal(1, chained.rows[2][3])
    end)
end)

-- In normal mode the current line is the argument, unless it is blank.
describe("<leader>Tn", function()
    it("prefills the command on a blank line", function()
        local new = assert(vim.fn.maparg("<leader>Tn", "n", false, true).callback)
        set({ "A and B", "" }, 2, 0)
        assert.are.equal(":TruthTable ", new())
    end)

    it("builds the table from the current line, in its place", function()
        set({ "A and B", "" }, 1, 0)
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<leader>Tn", true, false, true), "x", false)
        local from_line = assert(core.parse(vim.api.nvim_buf_get_lines(0, 0, 6, false)))
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
        assert.are.equal("Rows 1 and 2 agree on every input but disagree on B", notified)
        assert.are.same(table_lines, buffer())
    end)
end)
