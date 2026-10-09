-- Rewrite previews: a rewrite command shows its result as virtual text beside
-- the line, and the buffer stays as it was until an apply command writes the
-- result, in place or as the next step of a derivation.
-- The menu of every rewrite skips the preview: a pick is written at once.
-- The plugin keeps its pending preview per buffer, so every case starts in a
-- fresh one: a preview that a failed case left behind cannot reach the next.
-- Runs inside Neovim (make test-nvim): busted with nlua as its interpreter.
vim.opt.rtp:append(vim.fn.getcwd())
require("truth-table").setup()

local core = require("truth-table.core")
local markdown = require("truth-table.markdown")
local model = require("truth-table.table_model")
local ns = vim.api.nvim_get_namespaces()["truth-table.preview"]

local function marks()
    return vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
end

-- The pending preview's virtual text, its chunks joined, or nil when none is
-- shown.
local function text()
    local mark = marks()[1]
    if not mark then
        return nil
    end
    local parts = {}
    for _, chunk in ipairs(mark[4].virt_text) do
        parts[#parts + 1] = chunk[1]
    end
    return table.concat(parts)
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

-- The marks of a namespace as the text under each with its group, in order
-- of row, column and text.
local function regions(name)
    local found = {}
    local space = vim.api.nvim_get_namespaces()[name]
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, space, 0, -1, { details = true })) do
        -- A mark an edit has orphaned, before its scheduled removal, may point
        -- past the buffer.
        local line = vim.api.nvim_buf_get_lines(0, mark[2], mark[2] + 1, false)[1] or ""
        found[#found + 1] = { row = mark[2] + 1, col = mark[3], text = line:sub(mark[3] + 1, mark[4].end_col or mark[3]), group = mark[4].hl_group }
    end
    table.sort(found, function(a, b)
        if a.row ~= b.row then
            return a.row < b.row
        elseif a.col ~= b.col then
            return a.col < b.col
        end
        return a.text < b.text
    end)
    for _, region in ipairs(found) do
        region.col = nil
    end
    return found
end

-- What written rewrites lit, to stay with their lines.
local function lit()
    return regions("truth-table.changed")
end

-- The consumed terms of the pending preview.
local function targets()
    return regions("truth-table.target")
end

describe("preview.active", function()
    local active = require("truth-table.preview").active

    it("is nil with no preview pending", function()
        set({ "not (A and B)" })
        assert.is_nil(active(vim.api.nvim_get_current_buf()))
    end)

    it("is the pending preview, carrying its law", function()
        set({ "not (A and B)" })
        vim.cmd("TruthTableDeMorgan")
        local pending = assert(active(vim.api.nvim_get_current_buf()))
        assert.are.equal("De Morgan", pending.law)
    end)

    it("is nil once the buffer changes, with no notice and no dismissal of its own", function()
        set({ "not (A and B)" })
        vim.cmd("TruthTableDeMorgan")
        vim.api.nvim_buf_set_lines(0, 0, 0, false, { "prose above" })
        assert.is_nil(active(vim.api.nvim_get_current_buf()))
        assert.is_nil(notified)
    end)
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

    it("shows the other swap when the ! form follows the plain one", function()
        set({ "A ∧ B ∧ C" })
        on("B")
        vim.cmd("TruthTableCommute")
        assert.are.equal(" ⇒ A ∧ C ∧ B  | by commutativity", text())
        vim.cmd("TruthTableCommute!")
        assert.are.equal(1, #marks())
        assert.are.equal(" ⇒ B ∧ A ∧ C  | by commutativity", text())
    end)

    it("previews at the new place in one press when the same command runs after the cursor moved", function()
        set({ "not (A and B)", "not (C or D)" })
        vim.cmd("TruthTableDeMorgan")
        assert.are.equal(" ⇒ ¬A ∨ ¬B  | by De Morgan", text())
        vim.api.nvim_win_set_cursor(0, { 2, 0 })
        vim.cmd("TruthTableDeMorgan")
        assert.are.equal(1, #marks())
        assert.are.equal(" ⇒ ¬C ∧ ¬D  | by De Morgan", text())
        assert.are.equal(2, marks()[1][2] + 1)
    end)

    it("keeps the pending preview when the command finds nothing at the new place", function()
        set({ "not (A and B)", "prose" })
        vim.cmd("TruthTableDeMorgan")
        vim.api.nvim_win_set_cursor(0, { 2, 0 })
        vim.cmd("TruthTableDeMorgan")
        assert.is_truthy(notified)
        assert.are.equal(1, #marks())
        assert.are.equal(" ⇒ ¬A ∨ ¬B  | by De Morgan", text())
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

describe("an unfold preview", function()
    it("shows the connective's definition beside the line, from the symbol or an operand", function()
        set({ "  R and (T implies E)" })
        on("implies")
        vim.cmd("TruthTableUnfold")
        assert.are.equal("  R and (T implies E)", vim.api.nvim_get_current_line())
        assert.are.equal(1, #marks())
        assert.are.equal(" ⇒ R ∧ (¬T ∨ E)  | by definition of →", text())
        vim.cmd("TruthTableUnfold")
        assert.are.equal(0, #marks())
        on("E")
        vim.cmd("TruthTableUnfold")
        assert.are.equal(" ⇒ R ∧ (¬T ∨ E)  | by definition of →", text())
    end)

    it("takes the outermost connective from a column heading", function()
        set({ "| a | b | a ⊕ b |", "|:-:|:-:|:-----:|", "| 0 | 0 |   0   |" })
        on("a ⊕ b")
        vim.cmd("TruthTableUnfold")
        assert.are.equal(1, #marks())
        assert.are.equal(" [column 3] ⇒ (a ∧ ¬b) ∨ (¬a ∧ b)  | by definition of ⊕", text())
    end)

    it("is written as a step by :TruthTableApplyStep", function()
        set({ "a ⇔ b" })
        on("⇔")
        vim.cmd("TruthTableUnfold")
        vim.cmd("TruthTableApplyStep")
        assert.are.same({ "a ⇔ b", "≡ (a ∧ b) ∨ (¬a ∧ ¬b)    | by definition of ⇔" }, lines())
    end)
end)

describe("a normal form preview", function()
    it("shows the whole expression in the form, wherever the cursor is", function()
        set({ "  (a or b) and c" })
        on("c")
        vim.cmd("TruthTableDNF")
        assert.are.equal("  (a or b) and c", vim.api.nvim_get_current_line())
        assert.are.equal(1, #marks())
        assert.are.equal(" ⇒ (a ∧ c) ∨ (b ∧ c)  | by disjunctive normal form", text())
        vim.cmd("TruthTableDNF")
        assert.are.equal(0, #marks())
        on("(a")
        vim.cmd("TruthTableCNF")
        assert.are.equal(0, #marks())
        assert.are.equal("Already in conjunctive normal form", notified)
    end)

    it("takes a column heading", function()
        set({ "| a | b | a → b |", "|:-:|:-:|:-----:|", "| 0 | 0 |   1   |" })
        on("a → b")
        vim.cmd("TruthTableCNF")
        assert.are.equal(1, #marks())
        assert.are.equal(" [column 3] ⇒ ¬a ∨ b  | by conjunctive normal form", text())
    end)

    it("is written as a step by :TruthTableApplyStep", function()
        set({ "a xor b" })
        on("xor")
        vim.cmd("TruthTableDNF")
        vim.cmd("TruthTableApplyStep")
        assert.are.same({ "a xor b", "≡ (a ∧ ¬b) ∨ (¬a ∧ b)    | by disjunctive normal form" }, lines())
    end)
end)

describe("a refusal", function()
    it("from Unfold names Xor when Xor applies at this cursor", function()
        set({ "(not T and E) or (T and not E)" })
        on("T")
        vim.cmd("TruthTableUnfold")
        assert.are.equal(0, #marks())
        assert.are.equal(
            "No →, ⊕ or ⇔ under the cursor or in the expression; to recognise ⊕ or ⇔ in the terms, use :TruthTableXor",
            notified
        )
    end)

    it("from Xor names Unfold when Unfold applies at this cursor", function()
        set({ "T xor E" })
        on("T")
        vim.cmd("TruthTableXor")
        assert.are.equal(0, #marks())
        assert.are.equal(
            "No pair of terms under the cursor forms ⊕ or ⇔; to replace a connective by its definition, use :TruthTableUnfold",
            notified
        )
    end)

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
        return core.format(assert(model.parse(headers, rows)))
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
        assert.are.equal("¬A ∨ ¬B", markdown.row(updated[1])[2])
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
        assert.are.equal("B ∧ A", markdown.row(renamed[1])[3])
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

-- :TruthTableRewrites shows its menu through vim.ui.select. The stand-in that
-- takes its place for this group records the menu as it was shown and picks
-- the entry whose result is `choosing`, or cancels when that is nil.
describe("the rewrite menu", function()
    local offered, choosing, while_open, select

    setup(function()
        select = vim.ui.select
        vim.ui.select = function(items, opts, on_choice)
            offered = { prompt = opts.prompt, kind = opts.kind }
            local picked, index
            for i, item in ipairs(items) do
                offered[i] = opts.format_item(item)
                if item.text == choosing then
                    picked, index = item, i
                end
            end
            if while_open then
                while_open()
            end
            on_choice(picked, index)
        end
    end)

    teardown(function()
        vim.ui.select = select
    end)

    before_each(function()
        offered, choosing, while_open = nil, nil, nil
    end)

    local function rewrites(pick)
        offered, choosing = nil, pick
        vim.cmd("TruthTableRewrites")
    end

    -- The entries of the menu, without its prompt and kind.
    local function entries()
        return { unpack(offered) }
    end

    local function format(headers, rows)
        return core.format(assert(model.parse(headers, rows)))
    end

    local source = "(a and b) or (not a and b)"

    it("lists every rewrite of the expression, each as its result and its law, the bars in one column", function()
        local widest = vim.fn.strdisplaywidth("(a ∨ (¬a ∧ b)) ∧ (b ∨ (¬a ∧ b))")
        set({ source }, 1, 4)
        rewrites(nil)
        assert.are.equal("Rewrites of " .. source, offered.prompt)
        assert.are.equal("truth-table.rewrite", offered.kind)
        assert.are.same({
            justified("b", widest + 2, "reduction"),
            justified("b ∧ (a ∨ ¬a)", widest + 2, "distributivity (factoring)"),
            justified("((a ∧ b) ∨ ¬a) ∧ ((a ∧ b) ∨ b)", widest + 2, "distributivity (distributing)"),
            justified("(a ∨ (¬a ∧ b)) ∧ (b ∨ (¬a ∧ b))", widest + 2, "distributivity (distributing)"),
            justified("(¬a ∧ b) ∨ (a ∧ b)", widest + 2, "commutativity"),
            justified("(b ∧ a) ∨ (¬a ∧ b)", widest + 2, "commutativity"),
            justified("(a ∧ b) ∨ (b ∧ ¬a)", widest + 2, "commutativity"),
        }, entries())
    end)

    it("writes the pick below as a justified step, and the cursor follows it", function()
        set({ source }, 1, 4)
        rewrites("b")
        assert.are.same({
            source,
            justified("≡ b", vim.fn.strdisplaywidth(source) + 4, "reduction"),
        }, lines())
        assert.are.same({ 2, #"≡ " }, vim.api.nvim_win_get_cursor(0))
        assert.is_nil(notified)
    end)

    it("reads the step the cursor is now on next, and shows no menu when no rewrite applies to it", function()
        set({ source }, 1, 4)
        rewrites("b")
        rewrites("b")
        assert.is_nil(offered)
        assert.are.equal("No rewrite applies to b", notified)
    end)

    it("writes nothing when cancelled, and dismisses a pending preview as it opens", function()
        set({ "A ∧ B" })
        vim.cmd("TruthTableCommute")
        assert.are.equal(1, #marks())
        rewrites(nil)
        assert.are.equal(1, #entries())
        assert.are.equal(0, #marks())
        assert.is_nil(notified)
        assert.are.same({ "A ∧ B" }, lines())
    end)

    it("steps from the side of a derivation line that the cursor is on", function()
        set({ "F ≡ A ∧ B" }, 1, 6)
        rewrites("B ∧ A")
        assert.are.same({ "F ≡ A ∧ B", "  ≡ B ∧ A    | by commutativity" }, lines())
    end)

    it("leaves a buffer that was edited while the menu was open as edited, and says so", function()
        set({ "A ∧ B" })
        while_open = function()
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "C ∧ D" })
        end
        rewrites("B ∧ A")
        assert.are.same({ "C ∧ D" }, lines())
        assert.are.equal("The buffer changed while the menu was open; nothing was written", notified)
    end)

    -- A heading has no steps.
    it("renames a table heading in place, from any row of its column", function()
        local constant = format({ "A", "A ∨ ¬A" }, { { "0", "1" }, { "1", "1" } })
        set(constant, 3, 10)
        rewrites("1")
        assert.are.same({ "1       | by complement", "¬A ∨ A  | by commutativity" }, entries())
        local collapsed = lines()
        assert.are.equal("1", markdown.row(collapsed[1])[2])
        assert.are.same(vim.list_slice(constant, 2), vim.list_slice(collapsed, 2))
        assert.are.equal("Renamed the heading; update explicit references to its old label if needed", notified)
    end)

    it("refuses a pick that would duplicate another heading, as a preview is refused", function()
        local clash = format({ "A ∧ B", "B ∧ A" }, { { "1", "1" } })
        set(clash)
        on("A ∧")
        rewrites("B ∧ A")
        assert.is_truthy(notified:find("duplicate", 1, true), notified)
        assert.are.same(clash, lines())
    end)

    it("is not shown when there is no expression under the cursor", function()
        set({ "" })
        rewrites(nil)
        assert.is_nil(offered)
        assert.are.equal("No expression under the cursor", notified)
    end)
end)

describe("what a rewrite consumed and put in", function()
    local group, consumed = "TruthTableChanged", "TruthTableConsumed"

    it("is lit in the preview's text, between the dimmed rest", function()
        set({ "r and not (s or t)" })
        on("not")
        vim.cmd("TruthTableDeMorgan")
        assert.are.same({
            { " ⇒ r ∧ ", "Comment" },
            { "¬s ∧ ¬t", group },
            { "  | by De Morgan", "Comment" },
        }, marks()[1][4].virt_text)
    end)

    it("lights the consumed terms on the line while the preview is pending, and no longer once it is dismissed", function()
        set({ "a ∧ b ∨ c" })
        on("a")
        vim.cmd("TruthTableCommute")
        assert.are.same({
            { row = 1, text = "a", group = consumed },
            { row = 1, text = "b", group = consumed },
        }, targets())
        vim.cmd("TruthTableCommute")
        assert.are.same({}, targets())
        assert.are.same({}, lit())
    end)

    it("drops the consumed marks with a preview the buffer invalidated", function()
        set({ "not (A or B)" })
        vim.cmd("TruthTableDeMorgan")
        assert.are.equal(1, #targets())
        set({ "A and B" })
        vim.wait(100, function()
            return #targets() == 0
        end)
        assert.are.same({}, targets())
    end)

    it("is lit on the step it is written as, with what it consumed above, and stays as the next step is written", function()
        set({ "r and not (s or t)" })
        on("not")
        vim.cmd("TruthTableDeMorgan")
        vim.cmd("TruthTableApplyStep")
        assert.are.same({}, targets())
        assert.are.same({
            { row = 1, text = "not (s or t)", group = consumed },
            { row = 2, text = "¬s ∧ ¬t", group = group },
        }, lit())
        on("r", 2)
        vim.cmd("TruthTableCommute")
        vim.cmd("TruthTableApplyStep")
        assert.are.same({
            { row = 1, text = "not (s or t)", group = consumed },
            { row = 2, text = "r", group = consumed },
            { row = 2, text = "¬s", group = consumed },
            { row = 2, text = "¬s ∧ ¬t", group = group },
            { row = 3, text = "¬s ∧ r", group = group },
        }, lit())
    end)

    it("lights the consumed terms of a pick from the menu with its step", function()
        local picked
        local select = vim.ui.select
        vim.ui.select = function(items, _, choose)
            for _, item in ipairs(items) do
                if item.text == picked then
                    choose(item)
                    return
                end
            end
        end
        finally(function()
            vim.ui.select = select
        end)
        set({ "A ∧ B" })
        picked = "B ∧ A"
        vim.cmd("TruthTableRewrites")
        assert.are.same({
            { row = 1, text = "A", group = consumed },
            { row = 1, text = "B", group = consumed },
            { row = 2, text = "B ∧ A", group = group },
        }, lit())
    end)

    it("is lit on a line rewritten in place, and a second rewrite there replaces it", function()
        set({ "A or not (B and C)" })
        on("not")
        vim.cmd("TruthTableDeMorgan")
        vim.cmd("TruthTableApply")
        assert.are.equal("A ∨ ¬B ∨ ¬C", vim.api.nvim_get_current_line())
        assert.are.same({ { row = 1, text = "¬B ∨ ¬C", group = group } }, lit())
        on("¬B")
        vim.cmd("TruthTableCommute")
        vim.cmd("TruthTableApply")
        assert.are.same({ { row = 1, text = "¬C ∨ ¬B", group = group } }, lit())
    end)

    it("is lit in a heading rewritten in place, whose consumed term was lit while pending", function()
        set(core.format({ headers = { "A", "B", "A ∧ ¬(A ∧ B)" }, rows = { { 0, 0, 0 }, { 1, 0, 1 } }, encoding = "bits" }), 1, 20)
        on("¬(")
        vim.cmd("TruthTableDeMorgan")
        assert.are.same({ { row = 1, text = "¬(A ∧ B)", group = consumed } }, targets())
        vim.cmd("TruthTableApply")
        assert.are.same({}, targets())
        assert.are.equal("A ∧ (¬A ∨ ¬B)", markdown.row(lines()[1])[3])
        assert.are.same({ { row = 1, text = "(¬A ∨ ¬B)", group = group } }, lit())
    end)

    it("follows the reader's edits on the line", function()
        set({ "A or not (B and C)" })
        on("not")
        vim.cmd("TruthTableDeMorgan")
        vim.cmd("TruthTableApply")
        vim.api.nvim_buf_set_text(0, 0, 0, 0, 0, { "  " })
        assert.are.same({ { row = 1, text = "¬B ∨ ¬C", group = group } }, lit())
    end)

    it("has its groups defined as default links, again after a colorscheme", function()
        for name, link in pairs({ [group] = "DiagnosticOk", [consumed] = "DiagnosticWarn" }) do
            local hl = vim.api.nvim_get_hl(0, { name = name })
            assert.are.equal(link, hl.link, name)
            assert.is_true(hl.default, name)
            vim.cmd("highlight clear " .. name)
            vim.api.nvim_exec_autocmds("ColorScheme", {})
            assert.are.equal(link, vim.api.nvim_get_hl(0, { name = name }).link, name)
        end
    end)
end)

describe("editor patches and undo", function()
    local function settle()
        vim.wait(20, function() return false end, 1)
    end

    it("undoes and redoes a step's text and annotations together", function()
        set({ "not (A or B)" })
        vim.cmd("TruthTableDeMorgan")
        vim.cmd("TruthTableApplyStep")
        local written, highlights = lines(), lit()
        assert.are.equal(2, #highlights)
        vim.cmd("undo")
        settle()
        assert.are.same({ "not (A or B)" }, lines())
        assert.are.same({}, lit())
        vim.cmd("redo")
        settle()
        assert.are.same(written, lines())
        assert.are.same(highlights, lit())
    end)

    it("clears marks when undo passes the first annotated history entry", function()
        set({ "not (A or B)" })
        vim.cmd("TruthTableDeMorgan")
        vim.cmd("TruthTableApplyStep")
        vim.cmd("undo")
        vim.cmd("undo")
        settle()
        assert.are.same({ "" }, lines())
        assert.are.same({}, lit())
        vim.cmd("redo")
        vim.cmd("redo")
        settle()
        assert.are.equal(2, #lit())
    end)

    it("restores the previous annotations when an in-place rewrite is undone", function()
        set({ "A or not (B and C)" })
        on("not")
        vim.cmd("TruthTableDeMorgan")
        vim.cmd("TruthTableApply")
        local first_text, first_marks = lines(), lit()
        on("¬B")
        vim.cmd("TruthTableCommute")
        vim.cmd("TruthTableApply")
        local second_text, second_marks = lines(), lit()
        vim.cmd("undo")
        settle()
        assert.are.same(first_text, lines())
        assert.are.same(first_marks, lit())
        vim.cmd("redo")
        settle()
        assert.are.same(second_text, lines())
        assert.are.same(second_marks, lit())
        vim.cmd("undo")
        vim.cmd("undo")
        settle()
        assert.are.same({ "A or not (B and C)" }, lines())
        assert.are.same({}, lit())
    end)

    it("keeps annotations associated with native undo branches", function()
        set({ "not (A or B)" })
        vim.cmd("TruthTableDeMorgan")
        vim.cmd("TruthTableApplyStep")
        local branch_one, marks_one = lines(), lit()
        vim.cmd("undo")
        settle()
        on("A")
        vim.cmd("TruthTableCommute")
        vim.cmd("TruthTableApply")
        local branch_two, marks_two = lines(), lit()
        vim.cmd("undo")
        settle()
        assert.are.same({}, lit())
        vim.cmd("redo")
        settle()
        assert.are.same(branch_two, lines())
        assert.are.same(marks_two, lit())
        vim.cmd("undo 2")
        settle()
        assert.are.same(branch_one, lines())
        assert.are.same(marks_one, lit())
    end)

    it("restores annotations around an ordinary edit between rewrites", function()
        set({ "A or not (B and C)" })
        on("not")
        vim.cmd("TruthTableDeMorgan")
        vim.cmd("TruthTableApply")
        local original = lit()
        vim.cmd("let &undolevels = &undolevels")
        vim.api.nvim_buf_set_text(0, 0, 0, 0, 0, { "  " })
        settle()
        assert.are.equal("¬B ∨ ¬C", lit()[1].text)
        vim.cmd("undo")
        settle()
        assert.are.same(original, lit())
        vim.cmd("undo")
        settle()
        assert.are.same({}, lit())
        vim.cmd("redo")
        vim.cmd("redo")
        settle()
        assert.are.equal("¬B ∨ ¬C", lit()[1].text)
    end)
end)

describe("aligning a derivation", function()
    -- The display column of each justification bar in the buffer, in order.
    local function bars()
        local columns = {}
        for _, line in ipairs(lines()) do
            local bar = line:find("| by", 1, true)
            if bar then
                columns[#columns + 1] = vim.fn.strdisplaywidth(line:sub(1, bar - 1))
            end
        end
        return columns
    end

    local function step(row, needle, command)
        on(needle, row)
        vim.cmd(command)
        vim.cmd("TruthTableApplyStep")
    end

    it("keeps every bar in one column as steps grow wider, and the marks on their expressions", function()
        set({ "(¬C ∨ (Q ∧ ¬L)) ∧ Q" })
        step(1, ") ∧ Q", "TruthTableCommute")
        step(2, "Q", "TruthTableDistribute")
        assert.are.same({ 29, 29 }, bars())
        step(3, "(Q", "TruthTableSimplify")
        step(4, "Q", "TruthTableFactor")
        assert.are.same({ 29, 29, 29, 29 }, bars())
        assert.are.equal("≡ Q ∧ (¬C ∨ (Q ∧ ¬L))        | by commutativity", lines()[2])
        local produced = vim.tbl_filter(function(region)
            return region.row == 2 and region.group == "TruthTableChanged"
        end, lit())
        assert.are.same({ { row = 2, text = "Q ∧ (¬C ∨ (Q ∧ ¬L))", group = "TruthTableChanged" } }, produced)
    end)

    it("undoes a step and the realignment it caused together", function()
        set({ "(¬C ∨ (Q ∧ ¬L)) ∧ Q" })
        step(1, ") ∧ Q", "TruthTableCommute")
        local before = lines()
        step(2, "Q", "TruthTableDistribute")
        assert.are_not.same(before[2], lines()[2])
        vim.cmd("silent undo")
        assert.are.same(before, lines())
    end)

    it("realigns after a rewrite in place that changed a step's width", function()
        set({ "¬(A ∧ B) ∨ C", "≡ ¬A ∨ ¬B ∨ C    | by De Morgan" })
        on("¬A", 2)
        vim.cmd("TruthTableDeMorgan")
        vim.cmd("TruthTableApply")
        assert.are.same({ "¬(A ∧ B) ∨ C", "≡ ¬(A ∧ B) ∨ C    | by De Morgan, De Morgan" }, lines())
    end)

    it("aligns a derivation typed by hand with :TruthTableAlign, from any of its lines", function()
        set({ "head", "≡ a  | by x", "≡ a ∧ b ∧ c      | by y", "" }, 2, 0)
        vim.cmd("TruthTableAlign")
        assert.are.same({ "head", "≡ a            | by x", "≡ a ∧ b ∧ c    | by y", "" }, lines())
    end)

    it("fires TruthTableRewrite with the buffer, the row and the kind of each written rewrite", function()
        local heard = {}
        local id = vim.api.nvim_create_autocmd("User", {
            pattern = "TruthTableRewrite",
            callback = function(event)
                heard[#heard + 1] = event.data
            end,
        })
        finally(function()
            vim.api.nvim_del_autocmd(id)
        end)
        set({ "not (A or B)" })
        vim.cmd("TruthTableDeMorgan")
        vim.cmd("TruthTableApplyStep")
        vim.cmd("TruthTableDeMorgan")
        vim.cmd("TruthTableApply")
        local buf = vim.api.nvim_get_current_buf()
        assert.are.same({ { buf = buf, row = 2, kind = "step" }, { buf = buf, row = 2, kind = "in_place" } }, heard)
    end)
end)

describe("the transient apply keys", function()
    local function press(keys)
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
    end

    -- How many of the buffer's normal-mode maps are the preview's own.
    local function apply_keys()
        local count = 0
        for _, map in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
            if (map.desc or ""):find("apply preview", 1, true) then
                count = count + 1
            end
        end
        return count
    end

    it("appear with a preview, and <Space> writes it in place and removes them", function()
        set({ "  not (A and B)" })
        vim.cmd("TruthTableDeMorgan")
        assert.are.equal(2, apply_keys())
        press("<Space>")
        assert.are.equal("  ¬A ∨ ¬B", vim.api.nvim_get_current_line())
        assert.are.equal(0, #marks())
        assert.are.equal(0, apply_keys())
    end)

    it("write the step below on <CR>, and the cursor follows it", function()
        set({ "A ∧ B" })
        vim.cmd("TruthTableCommute")
        press("<CR>")
        assert.are.same({ "A ∧ B", "≡ B ∧ A    | by commutativity" }, lines())
        assert.are.equal(2, vim.api.nvim_win_get_cursor(0)[1])
        assert.are.equal(0, apply_keys())
    end)

    it("go when the preview is toggled away, and <CR> is plain movement again", function()
        set({ "not (A and B)", "below" })
        vim.cmd("TruthTableDeMorgan")
        vim.cmd("TruthTableDeMorgan")
        assert.are.equal(0, apply_keys())
        press("<CR>")
        assert.are.same({ "not (A and B)", "below" }, lines())
        assert.are.equal(2, vim.api.nvim_win_get_cursor(0)[1])
    end)

    it("go when an edit invalidates the preview", function()
        set({ "not (A and B)" })
        vim.cmd("TruthTableDeMorgan")
        set({ "A and B" })
        -- The edit schedules the keys' removal with the stale mark's.
        vim.wait(100, function()
            return apply_keys() == 0
        end)
        assert.are.equal(0, apply_keys())
    end)

    it("shadow a buffer-local map while pending, and put it back after", function()
        set({ "A ∧ B" })
        vim.keymap.set("n", "<CR>", "G", { buffer = 0 })
        vim.cmd("TruthTableCommute")
        press("<CR>")
        assert.are.same({ "A ∧ B", "≡ B ∧ A    | by commutativity" }, lines())
        local restored = vim.fn.maparg("<CR>", "n", false, true)
        assert.are.equal("G", restored.rhs)
        assert.are.equal(1, restored.buffer)
    end)

    it("warn on <CR> over a heading and stay; <Space> still renames it", function()
        local heading_table = core.format(assert(model.parse({ "A", "B", "A ∧ B" }, { { "0", "0", "0" }, { "1", "1", "1" } })))
        set(heading_table)
        on("A ∧")
        vim.cmd("TruthTableCommute")
        -- The preview itself notified (applying renames the heading).
        notified = nil
        press("<CR>")
        assert.are.equal("Steps apply to expression lines; use :TruthTableApply for a heading", notified)
        assert.are.equal(1, #marks())
        assert.are.equal(2, apply_keys())
        press("<Space>")
        assert.are.equal("B ∧ A", markdown.row(lines()[1])[3])
        assert.are.equal(0, apply_keys())
    end)
end)
