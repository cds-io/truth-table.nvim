-- Rewrite previews: a rewrite command shows its result as virtual text beside
-- the line, and the buffer stays as it was until an apply command writes the
-- result, in place or as the next step of a derivation.
-- The plugin keeps its pending preview per buffer, so every case starts in a
-- fresh one: a preview that a failed case left behind cannot reach the next.
-- Runs inside Neovim (make test-nvim): busted with nlua as its interpreter.
vim.opt.rtp:append(vim.fn.getcwd())
require("truth-table").setup()

local core = require("truth-table.core")
local ns = vim.api.nvim_get_namespaces()["truth-table.preview"]

local function marks()
    return vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
end

-- The pending preview's virtual text, or nil when none is shown.
local function text()
    return marks()[1] and marks()[1][4].virt_text[1][1]
end

local function lines()
    return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

local function set(content, row, col)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, content)
    vim.api.nvim_win_set_cursor(0, { row or 1, col or 0 })
end

-- Puts the cursor on the first byte of `needle`.
local function on(needle, row)
    row = row or 1
    local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
    vim.api.nvim_win_set_cursor(0, { row, assert(line:find(needle, 1, true)) - 1 })
end

-- A step with its justification's bar at a display column.
local function justified(step, column, law)
    return step .. string.rep(" ", column - vim.fn.strdisplaywidth(step)) .. "| by " .. law
end

local notified
vim.notify = function(message)
    notified = message
end

before_each(function()
    notified = nil
    vim.cmd("enew!")
end)

describe("a De Morgan preview", function()
    it("shows the rewrite beside the line and leaves the source as it was", function()
        set({ "  not (A and B)" })
        vim.cmd("TruthTableDeMorgan")
        assert.are.equal("  not (A and B)", vim.api.nvim_get_current_line())
        assert.are.equal(1, #marks())
        assert.are.equal(" ⇒ ¬A ∨ ¬B  | by De Morgan", text())
    end)

    it("is dismissed by running the command again", function()
        set({ "  not (A and B)" })
        vim.cmd("TruthTableDeMorgan")
        vim.cmd("TruthTableDeMorgan")
        assert.are.equal(0, #marks())
    end)

    it("is written in place by :TruthTableDeMorganApply, keeping the indentation", function()
        set({ "  not (A and B)" })
        vim.cmd("TruthTableDeMorgan")
        vim.cmd("TruthTableDeMorganApply")
        assert.are.equal("  ¬A ∨ ¬B", vim.api.nvim_get_current_line())
        assert.are.equal(0, #marks())
    end)

    it("cannot overwrite a source that changed after it was shown", function()
        set({ "not (A or B)" })
        vim.cmd("TruthTableDeMorgan")
        set({ "A and B" })
        vim.cmd("TruthTableDeMorganApply")
        assert.are.equal("A and B", vim.api.nvim_get_current_line())
        -- The edit schedules the stale mark's removal; give that its turn.
        vim.wait(100, function()
            return #marks() == 0
        end)
        assert.are.equal(0, #marks())
    end)

    it("rewrites a line with no separator as a whole", function()
        set({ "not (A and B)" })
        vim.cmd("TruthTableDeMorgan")
        vim.cmd("TruthTableDeMorganApply")
        assert.are.equal("¬A ∨ ¬B", vim.api.nvim_get_current_line())
    end)

    it("reaches the nearest match around the cursor", function()
        set({ "R ∧ (T ∨ E) ∧ (¬T ∨ ¬E)" })
        on("¬T")
        vim.cmd("TruthTableDeMorgan")
        assert.are.equal(" ⇒ R ∧ (T ∨ E) ∧ ¬(T ∧ E)  | by De Morgan", text())
    end)

    it("rewrites a nested negation the cursor is on, and applies it in place", function()
        set({ "A or not (B and C)" })
        on("not")
        vim.cmd("TruthTableDeMorgan")
        assert.are.equal(" ⇒ A ∨ ¬B ∨ ¬C  | by De Morgan", text())
        vim.cmd("TruthTableApply")
        assert.are.equal("A ∨ ¬B ∨ ¬C", vim.api.nvim_get_current_line())
    end)

    it("refuses when neither the cursor's operand nor the whole expression matches", function()
        set({ "A or not (B and C)" })
        vim.cmd("TruthTableDeMorgan")
        assert.are.equal(0, #marks())
        assert.is_truthy(notified:find("whole expression", 1, true), notified)
    end)

    it("is what the Lua entry point toggles in its no-argument form", function()
        set({ "not (A and B)" })
        require("truth-table.preview").toggle()
        assert.are.equal(" ⇒ ¬A ∨ ¬B  | by De Morgan", text())
        require("truth-table.preview").toggle()
        assert.are.equal(0, #marks())
    end)
end)

describe("a rewrite at the cursor", function()
    it("previews a factoring, then applies it in place, keeping the indentation", function()
        set({ "  S ∨ (A ∧ ¬C) ∨ (G ∧ ¬C)" })
        on("¬C")
        vim.cmd("TruthTableFactor")
        assert.are.equal(" ⇒ S ∨ (¬C ∧ (A ∨ G))  | by distributivity (factoring)", text())
        assert.are.equal("  S ∨ (A ∧ ¬C) ∨ (G ∧ ¬C)", vim.api.nvim_get_current_line())
        vim.cmd("TruthTableApply")
        assert.are.equal("  S ∨ (¬C ∧ (A ∨ G))", vim.api.nvim_get_current_line())
        assert.are.equal(0, #marks())
    end)

    it("is dismissed by the same command, here in its ! form", function()
        set({ "  S ∨ (¬C ∧ (A ∨ G))" })
        on("S")
        vim.cmd("TruthTableCommute")
        assert.are.equal(" ⇒ (¬C ∧ (A ∨ G)) ∨ S  | by commutativity", text())
        vim.cmd("TruthTableCommute!")
        assert.are.equal(0, #marks())
    end)

    it("is replaced by a different rewrite command's preview", function()
        set({ "  S ∨ (¬C ∧ (A ∨ G))" })
        on("S")
        vim.cmd("TruthTableCommute")
        on("¬C")
        vim.cmd("TruthTableDistribute")
        assert.are.equal(1, #marks())
        assert.are.equal(" ⇒ S ∨ (¬C ∧ A) ∨ (¬C ∧ G)  | by distributivity (distributing)", text())
        vim.cmd("TruthTableDistribute")
        assert.are.equal(0, #marks())
    end)

    it("applied in place on one side of ≡ keeps the other side and the spacing", function()
        set({ "F  ≡  A ∧ B" })
        on("A")
        vim.cmd("TruthTableCommute")
        vim.cmd("TruthTableApply")
        assert.are.equal("F  ≡  B ∧ A", vim.api.nvim_get_current_line())
    end)
end)

describe("a refusal", function()
    it("warns, shows no preview and leaves the buffer alone when the cursor is on an operator", function()
        set({ "  S ∨ (¬C ∧ (A ∨ G))" })
        on("∨")
        vim.cmd("TruthTableFactor")
        assert.are.equal(0, #marks())
        assert.are.equal("Put the cursor on an operand", notified)
        assert.are.same({ "  S ∨ (¬C ∧ (A ∨ G))" }, lines())
    end)

    -- Factor and Distribute are easy to reach for the wrong way round: a
    -- refusal names the other when it applies at this cursor, and only then.
    it("from Distribute names Factor when Factor applies at this cursor", function()
        set({ "(Q ∧ ¬C) ∨ (Q ∧ ¬L)" })
        on("Q")
        vim.cmd("TruthTableDistribute")
        assert.are.equal(0, #marks())
        assert.are.equal(
            "No neighbouring group to distribute Q into; to pull it out of the terms that share it, use :TruthTableFactor",
            notified
        )
    end)

    it("from Factor names Distribute when Distribute applies at this cursor", function()
        set({ "Q ∧ (¬C ∨ ¬L)" })
        on("Q")
        vim.cmd("TruthTableFactor")
        assert.are.equal(0, #marks())
        assert.are.equal(
            "Nothing to factor Q out of; to move it into the group beside it, use :TruthTableDistribute",
            notified
        )
    end)

    it("names no other command when neither Factor nor Distribute applies", function()
        set({ "Q ∧ R" })
        on("Q")
        vim.cmd("TruthTableDistribute")
        assert.are.equal("No neighbouring group to distribute Q into", notified)
        vim.cmd("TruthTableFactor")
        assert.are.equal("Nothing to factor Q out of", notified)
    end)

    it("says a dangling separator has no expression to rewrite", function()
        set({ "F ≡ " }, 1, 3)
        vim.cmd("TruthTableDeMorgan")
        assert.are.equal(0, #marks())
        assert.are.equal("No expression under the cursor", notified)
    end)

    it("says a blank line has no expression", function()
        set({ "" })
        vim.cmd("TruthTableFactor")
        assert.are.equal("No expression under the cursor", notified)
    end)

    it("asks for an operand when the cursor trails the expression, without touching the buffer", function()
        set({ "A ∧ B   " }, 1, 7)
        vim.cmd("TruthTableCommute")
        assert.are.equal("Put the cursor on an operand", notified)
        assert.are.equal("A ∧ B   ", vim.api.nvim_get_current_line())
    end)
end)

describe("a derivation step", function()
    -- Each step names its law, four columns clear of the wider line, and the
    -- next step's bar sits under it.
    it("goes under the Karnaugh line, one step after another, and the cursor follows", function()
        local head = "S ∨ (A ∧ ¬C) ∨ (G ∧ ¬C) ≡ S ∨ A ∧ ¬C ∨ G ∧ ¬C"
        local bar = vim.fn.strdisplaywidth(head) + 4
        local pad = string.rep(" ", 24)
        set({ head })
        on("¬C ∨ G")
        vim.cmd("TruthTableFactor")
        vim.cmd("TruthTableApplyStep")
        assert.are.same({
            head,
            justified(pad .. "≡ S ∨ (¬C ∧ (A ∨ G))", bar, "distributivity (factoring)"),
        }, lines())
        local cursor = vim.api.nvim_win_get_cursor(0)
        assert.are.equal(2, cursor[1])
        assert.are.equal(#(pad .. "≡ "), cursor[2])
        vim.cmd("TruthTableCommute")
        vim.cmd("TruthTableApplyStep")
        assert.are.same({
            head,
            justified(pad .. "≡ S ∨ (¬C ∧ (A ∨ G))", bar, "distributivity (factoring)"),
            justified(pad .. "≡ (¬C ∧ (A ∨ G)) ∨ S", bar, "commutativity"),
        }, lines())
        assert.are.equal(3, vim.api.nvim_win_get_cursor(0)[1])
        assert.are.equal(0, #marks())
    end)

    it("lands under the line that was previewed, wherever the cursor went", function()
        set({ "A ∧ B", "unrelated" })
        vim.cmd("TruthTableCommute")
        vim.api.nvim_win_set_cursor(0, { 2, 3 })
        vim.cmd("TruthTableApplyStep")
        assert.are.same({ "A ∧ B", "≡ B ∧ A    | by commutativity", "unrelated" }, lines())
        assert.are.equal(2, vim.api.nvim_win_get_cursor(0)[1])
    end)

    it("takes a De Morgan rewrite of the side under the cursor", function()
        set({ "  ≡ ¬(A ∧ B)" })
        vim.cmd("TruthTableDeMorgan")
        vim.cmd("TruthTableApplyStep")
        assert.are.same({ "  ≡ ¬(A ∧ B)", "  ≡ ¬A ∨ ¬B     | by De Morgan" }, lines())
    end)

    it("is refused for a stale preview, leaving the changed buffer alone", function()
        set({ "A ∧ B" })
        vim.cmd("TruthTableCommute")
        set({ "C ∧ D" })
        vim.cmd("TruthTableApplyStep")
        assert.are.same({ "C ∧ D" }, lines())
        assert.are.equal("No current preview; run a rewrite command first", notified)
    end)

    it("closes a derivation by recognising xor, the cursor anywhere in either term", function()
        local head = "(T ⊕ E) ∧ R ≡ R ∧ ((¬T ∧ E) ∨ (T ∧ ¬E))"
        set({ head })
        on("¬T")
        vim.cmd("TruthTableXor")
        assert.are.equal(" ⇒ R ∧ (T ⊕ E)  | by definition of ⊕", text())
        vim.cmd("TruthTableApplyStep")
        assert.are.same({
            head,
            justified("            ≡ R ∧ (T ⊕ E)", vim.fn.strdisplaywidth(head) + 4, "definition of ⊕"),
        }, lines())
    end)
end)

describe("a table heading", function()
    local function format(headers, rows)
        return assert(core.format_table(headers, rows))
    end

    local indented = format({ "A", "¬(A ∧ B)" }, { { "0", "1" }, { "1", "0" } })
    for i, line in ipairs(indented) do
        indented[i] = "  " .. line
    end
    local heading_table = format({ "A", "B", "A ∧ B" }, { { "0", "0", "0" }, { "1", "1", "1" } })
    local nested = format({ "A", "B", "A ∧ ¬(A ∧ B)" }, { { "0", "0", "0" }, { "1", "0", "1" } })

    it("is selected from a data row, and applying changes that heading only", function()
        set(indented, 3, 12)
        vim.cmd("TruthTableDeMorgan")
        assert.are.equal(1, #marks())
        assert.are.equal(0, marks()[1][2])
        assert.are.equal(" [column 2] ⇒ ¬A ∨ ¬B  | by De Morgan", text())
        vim.cmd("TruthTableDeMorganApply")
        local updated = lines()
        assert.are.equal("¬A ∨ ¬B", core.split_row(updated[1])[2])
        assert.are.equal("  ", updated[1]:sub(1, 2))
        -- Compared whole: a row that went missing fails here too.
        assert.are.same(vim.list_slice(indented, 2), vim.list_slice(updated, 2))
    end)

    it("refuses a De Morgan rewrite that would duplicate another heading, with no text edits", function()
        local duplicate = format({ "¬(A ∧ B)", "¬A ∨ ¬B" }, { { "1", "1" } })
        set(duplicate)
        vim.cmd("TruthTableDeMorgan")
        assert.are.equal(0, #marks())
        assert.is_truthy(notified:find("duplicate", 1, true), notified)
        assert.are.same(duplicate, lines())
    end)

    it("rewrites from the heading row, cursor in the cell, in place only", function()
        set(heading_table)
        on("A ∧")
        vim.cmd("TruthTableCommute")
        assert.are.equal(" [column 3] ⇒ B ∧ A  | by commutativity", text())
        -- The preview itself notified (applying renames the heading).
        notified = nil
        vim.cmd("TruthTableApplyStep")
        assert.are.equal("Steps apply to expression lines; use :TruthTableApply for a heading", notified)
        assert.are.equal(1, #marks())
        assert.are.same(heading_table, lines())
        vim.cmd("TruthTableApply")
        local renamed = lines()
        assert.are.equal("B ∧ A", core.split_row(renamed[1])[3])
        assert.are.same(vim.list_slice(heading_table, 2), vim.list_slice(renamed, 2))
    end)

    it("does not count the padding inside its cell as an operand", function()
        set(heading_table)
        vim.api.nvim_win_set_cursor(0, { 1, assert(heading_table[1]:find("A ∧", 1, true)) - 2 })
        vim.cmd("TruthTableCommute")
        assert.are.equal(0, #marks())
        assert.are.equal("Put the cursor on an operand", notified)
    end)

    it("offers no operand to point at from a data row", function()
        set(heading_table, 3, 14)
        vim.cmd("TruthTableCommute")
        assert.are.equal(0, #marks())
        assert.are.equal("Put the cursor on the heading row to choose an operand", notified)
    end)

    it("refuses a commute that would duplicate another heading", function()
        set(format({ "A ∧ B", "B ∧ A" }, { { "1", "1" } }))
        on("A ∧")
        vim.cmd("TruthTableCommute")
        assert.are.equal(0, #marks())
        assert.is_truthy(notified:find("duplicate", 1, true), notified)
    end)

    it("is read whole by Simplify from a data row", function()
        set(format({ "A", "A ∨ ¬A" }, { { "0", "1" }, { "1", "1" } }), 3, 10)
        vim.cmd("TruthTableSimplify")
        assert.are.equal(" [column 2] ⇒ 1  | by complement", text())
    end)

    it("lets the cursor pick a nested De Morgan match from the heading row", function()
        set(nested)
        on("¬")
        vim.cmd("TruthTableDeMorgan")
        assert.are.equal(" [column 3] ⇒ A ∧ (¬A ∨ ¬B)  | by De Morgan", text())
    end)

    it("still means the whole heading to De Morgan from a data row", function()
        set(nested, 3, 14)
        vim.cmd("TruthTableDeMorgan")
        assert.are.equal(0, #marks())
        assert.is_truthy(notified:find("whole expression", 1, true), notified)
    end)
end)

describe("Simplify", function()
    -- A derivation runs down justified lines: each step reads the expression
    -- and leaves the justification alone.
    it("applies the collapsing law nearest the cursor and names it, until none applies", function()
        set({ "(a and b) or (not a and b)" })
        on("b")
        vim.cmd("TruthTableFactor")
        vim.cmd("TruthTableApplyStep")
        vim.cmd("TruthTableSimplify")
        assert.are.equal(" ⇒ b ∧ 1  | by complement", text())
        vim.cmd("TruthTableApplyStep")
        vim.cmd("TruthTableSimplify")
        assert.are.equal(" ⇒ b  | by identity", text())
        vim.cmd("TruthTableApplyStep")
        assert.are.same({
            "(a and b) or (not a and b)",
            "≡ b ∧ (a ∨ ¬a)                | by distributivity (factoring)",
            "≡ b ∧ 1                       | by complement",
            "≡ b                           | by identity",
        }, lines())
        vim.cmd("TruthTableSimplify")
        assert.are.equal(0, #marks())
        assert.are.equal("No simplification applies to this expression", notified)
    end)

    it("does in one move what the three steps did", function()
        set({ "(a and b) or (not a and b)" })
        vim.cmd("TruthTableSimplify")
        assert.are.equal(" ⇒ b  | by reduction", text())
        vim.cmd("TruthTableSimplify")
        assert.are.equal(0, #marks())
    end)

    it("reads the line's expression when the cursor is in the justification", function()
        set({ "≡ b ∧ (a ∨ ¬a)    | by distributivity" })
        on("distributivity")
        vim.cmd("TruthTableSimplify")
        assert.are.equal(" ⇒ b ∧ 1  | by complement", text())
    end)

    -- The line still says how it follows from the one above.
    it("applied in place, adds its law to a justified line", function()
        set({ "≡ b ∧ (a ∨ ¬a)    | by distributivity" })
        on("distributivity")
        vim.cmd("TruthTableSimplify")
        vim.cmd("TruthTableApply")
        assert.are.equal("≡ b ∧ 1    | by distributivity, complement", vim.api.nvim_get_current_line())
    end)
end)
