-- The derivation check in a buffer: the first failing step's conclusion lit,
-- its ≡ shown as ≢, both gone on the next edit, and the verdict notified.
-- Runs inside Neovim (make test-nvim): busted with nlua as its interpreter.
vim.opt.rtp:append(vim.fn.getcwd())
require("truth-table").setup()

local NAMESPACE = "truth-table.verdict"

local function marks()
    local space = vim.api.nvim_get_namespaces()[NAMESPACE]
    return vim.api.nvim_buf_get_extmarks(0, space, 0, -1, { details = true })
end

-- The highlight marks as the text under each with its group and row (from
-- one), and the overlays as their text and row.
local function shown()
    local lit, overlays = {}, {}
    for _, mark in ipairs(marks()) do
        local row, col, detail = mark[2] + 1, mark[3], mark[4]
        local line = vim.api.nvim_buf_get_lines(0, mark[2], mark[2] + 1, false)[1] or ""
        if detail.virt_text then
            overlays[#overlays + 1] = { row = row, col = col, text = detail.virt_text[1][1], position = detail.virt_text_pos }
        else
            lit[#lit + 1] = { row = row, text = line:sub(col + 1, detail.end_col), group = detail.hl_group }
        end
    end
    return lit, overlays
end

local function set(content, row, col)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, content)
    vim.api.nvim_win_set_cursor(0, { row or 1, col or 0 })
end

local notified, level
vim.notify = function(message, at)
    notified, level = message, at
end

before_each(function()
    notified, level = nil, nil
    vim.cmd("enew!")
end)

describe(":TruthTableCheck", function()
    it("lights the first failing conclusion and overlays its ≡ with ≢", function()
        set({ "a ∨ b", "≡ a ∨ (b ∧ a)   | by absorption", "≡ a             | by absorption" })
        vim.cmd("TruthTableCheck")
        local lit, overlays = shown()
        assert.are.same({ { row = 2, text = "a ∨ (b ∧ a)", group = "TruthTableConsumed" } }, lit)
        assert.are.same({ { row = 2, col = 0, text = "≢", position = "overlay" } }, overlays)
        assert.are.equal("≡ a ∨ (b ∧ a)   | by absorption", vim.api.nvim_buf_get_lines(0, 1, 2, false)[1])
        assert.are.equal("step 1: a=0, b=1 gives 1 ≢ 0", notified)
        assert.are.equal(vim.log.levels.WARN, level)
    end)

    it("finds the block from any of its rows, and marks the failing row", function()
        set({ "", "a ∧ b", "≡ b ∧ a", "≡ b", "≡ b ∨ b", "" }, 5)
        vim.cmd("TruthTableCheck")
        local lit, overlays = shown()
        assert.are.same({ { row = 4, text = "b", group = "TruthTableConsumed" } }, lit)
        assert.are.equal(4, overlays[1].row)
        assert.are.equal("step 2: b=1, a=0 gives 0 ≢ 1", notified)
    end)

    it("overlays the ≡ of a conclusion in the middle of a line", function()
        local line = "F ≡ F ∧ F ≡ ¬F"
        set({ line })
        vim.cmd("TruthTableCheck")
        local _, overlays = shown()
        assert.are.equal((line:find("≡", 4, true)) - 1, overlays[1].col)
    end)

    it("says every step holds, with no marks", function()
        set({ "(a ∧ b) ∨ (¬a ∧ b)", "≡ b ∧ (a ∨ ¬a)", "≡ b" })
        vim.cmd("TruthTableCheck")
        assert.are.equal(0, #marks())
        assert.are.equal("every step holds (2 steps)", notified)
        assert.are.equal(vim.log.levels.INFO, level)
    end)

    it("says when there is no step to check", function()
        set({ "a ∧ b" })
        vim.cmd("TruthTableCheck")
        assert.are.equal("No ≡ step under the cursor", notified)
        set({ "| A | B |", "|---|---|", "| 0 | 1 |" }, 2)
        vim.cmd("TruthTableCheck")
        assert.are.equal("No ≡ step under the cursor", notified)
        assert.are.equal(0, #marks())
    end)

    it("reports a side it cannot judge, with no marks", function()
        set({ "a ∧ :h2", "≡ :h2 ∧ a" })
        vim.cmd("TruthTableCheck")
        assert.are.equal(":h2 has no meaning outside a table", notified)
        assert.are.equal(vim.log.levels.WARN, level)
        assert.are.equal(0, #marks())
    end)

    it("clears the marks on the next edit", function()
        set({ "a ∨ b", "≡ a" })
        vim.cmd("TruthTableCheck")
        assert.are.equal(2, #marks())
        vim.api.nvim_buf_set_lines(0, 1, 2, false, { "≡ b ∨ a" })
        -- The edit schedules the removal; give that its turn.
        vim.wait(100, function()
            return #marks() == 0
        end)
        assert.are.equal(0, #marks())
    end)

    it("replaces the last verdict's marks with the new one's", function()
        set({ "a ∨ b", "≡ a", "≡ a ∧ a" })
        vim.cmd("TruthTableCheck")
        vim.cmd("TruthTableCheck")
        local lit = shown()
        assert.are.equal(1, #lit)
        assert.are.equal(2, #marks())
    end)

    it("is mapped to <leader>ttv in the Rewrite family", function()
        local found
        for _, map in ipairs(vim.api.nvim_get_keymap("n")) do
            if map.rhs == "<Cmd>TruthTableCheck<CR>" then
                found = map
            end
        end
        assert.is_truthy(found)
        assert.are.equal("Rewrite: check the derivation", found.desc)
    end)
end)
