-- The equivalence marks in a buffer: a virtual line under the separator
-- with ≡ below the columns equivalent to the one at the cursor and ≢
-- below the rest, on by default, following the cursor while the global
-- switch is on, and gone with it. Runs inside Neovim (make test-nvim):
-- busted with nlua as its interpreter.
vim.opt.rtp:append(vim.fn.getcwd())
require("truth-table").setup()

local core = require("truth-table.core")
local equivalence = require("truth-table.equivalence")

-- p, q, p → q and ¬p ∨ q: the two spellings of the implication are one
-- class, the variables are singletons. Formatted by the plugin itself, so
-- the expected mark lines are the formatter's own geometry.
local TABLE = core.format(assert(core.build("p -> q | not p or q")))
local IMPLICATION = "   ≢     ≢      ≡       ≡"
local SINGLETON = "   ≡     ≢      ≢       ≢"
-- 0-based byte of a data cell's value on the first data row (ASCII there,
-- so bytes are display columns): p, p → q and ¬p ∨ q.
local P, IMPLIES, OR = 3, 16, 24

local function marks(buf)
    local space = vim.api.nvim_get_namespaces()["truth-table.equivalence"]
    if not space then
        return {}
    end
    return vim.api.nvim_buf_get_extmarks(buf or 0, space, 0, -1, { details = true })
end

-- The one mark line as { row (from one, the line it hangs below), text,
-- groups (one per column) }; nil for none.
local function shown()
    local found = marks()
    if #found == 0 then
        return nil
    end
    assert.are.equal(1, #found)
    local texts, groups = {}, {}
    for _, chunk in ipairs(found[1][4].virt_lines[1]) do
        texts[#texts + 1] = chunk[1]
        groups[#groups + 1] = chunk[2]
    end
    return { row = found[1][2] + 1, text = table.concat(texts), groups = groups }
end

-- A fresh scratch buffer per case, so no case reads another's marks.
local function fresh(content, row, col)
    vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, true))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, content)
    vim.api.nvim_win_set_cursor(0, { row, col })
end

-- The API moves the cursor without firing autocmds in this headless run,
-- so each move fires its event by hand.
local function move(row, col, event)
    vim.api.nvim_win_set_cursor(0, { row, col })
    vim.api.nvim_exec_autocmds(event or "CursorMoved", {})
end

local notified
vim.notify = function(message)
    notified = message
end

describe("the equivalence marks", function()
    -- The switch is global; every case starts from the default, on.
    before_each(function()
        equivalence.set(true)
    end)

    it("are on after setup: moving in a table paints them, no command", function()
        fresh(TABLE, 3, IMPLIES)
        move(3, IMPLIES)
        assert.are.same({
            row = 2,
            text = IMPLICATION,
            groups = {
                "TruthTableInequivalent",
                "TruthTableInequivalent",
                "TruthTableEquivalent",
                "TruthTableEquivalent",
            },
        }, shown())
    end)

    it("follow the cursor, the line keeping its height on a singleton column", function()
        fresh(TABLE, 3, IMPLIES)
        move(3, P)
        assert.are.equal(SINGLETON, shown().text)
        move(4, OR)
        assert.are.equal(IMPLICATION, shown().text)
    end)

    it(":TruthTableEquivalents toggles off everywhere, and back on", function()
        fresh(TABLE, 3, IMPLIES)
        move(3, IMPLIES)
        assert.is_truthy(shown())
        vim.cmd("TruthTableEquivalents")
        assert.is_nil(shown())
        assert.are.equal("Equivalence marks off", notified)
        -- Another buffer: the switch is global, not the buffer's.
        fresh(TABLE, 3, IMPLIES)
        move(3, IMPLIES)
        assert.is_nil(shown())
        -- Toggling back on paints at the cursor at once.
        vim.cmd("TruthTableEquivalents")
        assert.are.equal("Equivalence marks on", notified)
        assert.are.equal(IMPLICATION, shown().text)
    end)

    it("starts off when setup says equivalence = false", function()
        require("truth-table").setup({ equivalence = false })
        fresh(TABLE, 3, IMPLIES)
        move(3, IMPLIES)
        assert.is_nil(shown())
        -- The last setup wins: back to the default for the other cases.
        require("truth-table").setup()
    end)

    it("leave only the cursor's buffer marked", function()
        fresh(TABLE, 3, IMPLIES)
        move(3, IMPLIES)
        local left = vim.api.nvim_get_current_buf()
        assert.are.equal(1, #marks(left))
        vim.api.nvim_exec_autocmds("BufLeave", {})
        fresh({ "elsewhere" }, 1, 0)
        assert.are.same({}, marks(left))
    end)

    it("show nothing outside a table, and again inside one", function()
        local content = vim.list_extend(vim.list_slice(TABLE), { "", "prose" })
        fresh(content, 8, 0)
        move(8, 0)
        assert.is_nil(shown())
        move(3, IMPLIES)
        assert.are.equal(IMPLICATION, shown().text)
    end)

    it("treat a table mid-edit as navigation, not an error", function()
        fresh(TABLE, 3, IMPLIES)
        notified = nil
        vim.api.nvim_buf_set_lines(0, 2, 3, false, { "|  2  |  0  |   1   |   1    |" })
        move(3, IMPLIES, "TextChanged")
        assert.is_nil(shown())
        assert.is_nil(notified)
    end)

    it("mark nothing for a table with no data rows", function()
        fresh({ TABLE[1], TABLE[2] }, 1, IMPLIES)
        move(1, 0)
        assert.is_nil(shown())
    end)
end)
