-- Editor-only preview state. The source buffer remains unchanged until apply,
-- or until a rewrite is picked from the menu of them. The terms a rewrite
-- consumed are lit on its line while the preview is pending, and what it put
-- in is lit in the preview's text; a step written below keeps both, so a
-- derivation reads from the part a law acted on to the part it produced.
local predicate = require("truth-table.predicate")
local trees = require("truth-table.trees")
local markdown = require("truth-table.markdown")
local derivation = require("truth-table.derivation")
local rewrite = require("truth-table.rewrite")
local edit = require("truth-table.edit")
local M = {}
local namespace = vim.api.nvim_create_namespace("truth-table.preview")
-- The consumed terms of a pending preview, cleared with it.
local TARGET = vim.api.nvim_create_namespace("truth-table.target")
-- The lit regions of written rewrites stay with their lines.
local CHANGED_GROUP, CONSUMED_GROUP = "TruthTableChanged", "TruthTableConsumed"
local pending, attached = {}, {}

-- Each rewrite maps a located tree and a cursor byte to a new tree and the
-- name of the law that justifies it. `command` groups the names one user
-- command toggles; `whole` marks a rewrite that also works without a cursor
-- in the expression, on the whole of it. `opposite` names the rewrite a
-- reader is likely to have meant when this one refuses, with the words that
-- point to it.
local REWRITES = {
    de_morgan = { command = "de_morgan", whole = true, run = rewrite.de_morgan },
    simplify = { command = "simplify", whole = true, run = rewrite.simplify },
    factor = {
        command = "factor",
        run = rewrite.factor,
        opposite = { name = "distribute", hint = "to move it into the group beside it, use :TruthTableDistribute" },
    },
    distribute = {
        command = "distribute",
        run = rewrite.distribute,
        opposite = { name = "factor", hint = "to pull it out of the terms that share it, use :TruthTableFactor" },
    },
    xor = { command = "xor", run = rewrite.xor },
    commute = {
        command = "commute",
        run = function(ast, byte)
            return rewrite.commute(ast, byte, false)
        end,
    },
    commute_back = {
        command = "commute",
        run = function(ast, byte)
            return rewrite.commute(ast, byte, true)
        end,
    },
}

-- While a preview is pending, <Space> and <CR> apply it: <Space> in place,
-- <CR> as a ≡ step. Buffer-local, so they shadow the user's own maps only
-- while the preview shows; a buffer-local map they shadow is put back on
-- release. `saved[buf]` holds the shadowed maps and doubles as the
-- engaged flag.
local TRANSIENT = {
    {
        lhs = "<Space>",
        run = function()
            M.apply()
        end,
        desc = "Truth table: apply preview in place",
    },
    {
        lhs = "<CR>",
        run = function()
            M.apply_step()
        end,
        desc = "Truth table: apply preview as a ≡ step",
    },
}
local saved = {}

local function engage(buf)
    if saved[buf] then
        return
    end
    local shadowed = {}
    for _, key in ipairs(TRANSIENT) do
        -- maparg reads the current buffer's maps, so ask in `buf`'s context.
        local existing = vim.api.nvim_buf_call(buf, function()
            return vim.fn.maparg(key.lhs, "n", false, true)
        end)
        if existing.buffer == 1 then
            shadowed[key.lhs] = existing
        end
        vim.keymap.set("n", key.lhs, key.run, { buffer = buf, desc = key.desc })
    end
    saved[buf] = shadowed
end

local function release(buf)
    local shadowed = saved[buf]
    if not shadowed then
        return
    end
    saved[buf] = nil
    if not vim.api.nvim_buf_is_valid(buf) then
        return
    end
    for _, key in ipairs(TRANSIENT) do
        pcall(vim.keymap.del, "n", key.lhs, { buffer = buf })
    end
    vim.api.nvim_buf_call(buf, function()
        for _, dict in pairs(shadowed) do
            vim.fn.mapset("n", false, dict)
        end
    end)
end

local function dismiss(buf)
    pending[buf] = nil
    release(buf)
    vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
    vim.api.nvim_buf_clear_namespace(buf, TARGET, 0, -1)
end

local function watch(buf)
    if attached[buf] then
        return
    end
    attached[buf] = vim.api.nvim_buf_attach(buf, false, {
        on_lines = function()
            local preview = pending[buf]
            pending[buf] = nil
            if preview then
                -- A fast context: the extmark and the transient keymaps go
                -- once Neovim is ready. A preview engaged again by then owns
                -- the keymaps, so they stay.
                vim.schedule(function()
                    if vim.api.nvim_buf_is_valid(buf) then
                        pcall(vim.api.nvim_buf_del_extmark, buf, namespace, preview.mark)
                        for _, mark in ipairs(preview.targets or {}) do
                            pcall(vim.api.nvim_buf_del_extmark, buf, TARGET, mark)
                        end
                    end
                    if not pending[buf] then
                        release(buf)
                    end
                end)
            end
        end,
        on_detach = function()
            attached[buf], pending[buf], saved[buf] = nil, nil, nil
        end,
    })
end

-- A source is the expression the cursor selects, the byte from zero where it
-- `start`s in its line (nil when it is escaped there), plus the ways to
-- write a rendered rewrite, { text, law, produced, consumed }, back:
-- `replace(rewritten)` gives the edited line and the byte, from zero, where
-- the text starts in it (nil when the text is escaped there), and
-- `step(rewritten)`, for expression lines only, gives the line to insert
-- below and that byte. `offset` is the cursor's byte within the expression,
-- when it has one.

-- A heading is one expression, read from anywhere in its column. Only the
-- heading row itself puts the cursor on a byte of the expression.
local function heading_source(lines, bounds, at)
    local selected = {}
    for i = bounds.start_line, bounds.end_line do
        selected[#selected + 1] = lines[i]
    end
    local tbl, err = markdown.parse_table_lines(selected)
    if not tbl then
        return nil, err
    end
    local heading_line = lines[bounds.start_line]
    local column = math.min(markdown.column_index(lines[at.row], at.byte - 1), #tbl.headers)
    local expression = tbl.headers[column]
    local first, last = markdown.heading_cell(heading_line, column)
    -- An escaped heading does not map byte for byte (nor does it parse).
    local start = first and heading_line:sub(first, last) == expression and first - 1 or nil
    local offset
    if start and at.row == bounds.start_line then
        offset = at.byte - start
    end
    return {
        row = bounds.start_line,
        column = column,
        expression = expression,
        start = start,
        offset = offset,
        replace = function(rewritten)
            local replaced, reason = markdown.replace_heading(heading_line, column, rewritten.text)
            if not replaced then
                return nil, reason
            end
            local cell_first, cell_last = markdown.heading_cell(replaced, column)
            local written = cell_first and replaced:sub(cell_first, cell_last) == rewritten.text and cell_first - 1 or nil
            return replaced, written
        end,
    }
end

local function line_source(line, at)
    if markdown.is_table_line(line) then
        return nil, "Cursor is not inside a supported truth table"
    end
    local side, err = derivation.working_side(line, at.byte)
    if not side then
        return nil, err
    end
    return {
        row = at.row,
        expression = side.text,
        start = side.first - 1,
        offset = at.byte - side.first + 1,
        replace = function(rewritten)
            return derivation.replace(line, side, rewritten), side.first - 1
        end,
        step = function(rewritten)
            return derivation.step(line, rewritten, vim.fn.strdisplaywidth)
        end,
    }
end

-- The source the cursor selects and its located tree.
local function source_at(buf)
    local position = vim.api.nvim_win_get_cursor(0)
    local at = { row = position[1], byte = position[2] + 1 }
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local bounds = markdown.find_table(lines, at.row)
    local source, err
    if bounds then
        source, err = heading_source(lines, bounds, at)
    else
        source, err = line_source(lines[at.row], at)
    end
    if not source then
        return nil, err
    end
    local ast, parse_err = predicate.parse_located(source.expression)
    if not ast then
        return nil, parse_err
    end
    return source, ast
end

-- A rewrite as the source will write it: the consumed ranges lie in the
-- source expression's text, the produced ones in the text written.
local function rendered(rewritten)
    local change = rewritten.change
    return {
        text = trees.heading(rewritten.value), law = change.law,
        produced = change.produced_ranges, consumed = change.consumed_ranges,
    }
end

local function prepare(buf, source, rewritten)
    local replacement, written = source.replace(rewritten)
    if not replacement then
        return nil, written
    end
    local preview = {
        row = source.row - 1,
        replacement = replacement,
        written = written,
        source = source.start,
        heading = rewritten.text,
        law = rewritten.law,
        changed = rewritten.produced or {},
        consumed = rewritten.consumed or {},
        column = source.column,
        tick = vim.api.nvim_buf_get_changedtick(buf),
    }
    if source.step then
        preview.step, preview.step_column = source.step(rewritten)
    end
    return preview
end

local function resolve(buf, kind)
    local source, ast = source_at(buf)
    if not source then
        return nil, ast
    end
    if not kind.whole and not source.offset then
        return nil, "Put the cursor on the heading row to choose an operand"
    end
    -- A rewrite carries its law and both sides of the change.
    local rewritten, reason = kind.run(ast, source.offset)
    if not rewritten then
        -- Factor and Distribute are one law used from either side, and easy
        -- to reach for the wrong way round: say so when the other applies.
        local opposite = kind.opposite
        if opposite and REWRITES[opposite.name].run(ast, source.offset) then
            return nil, reason .. "; " .. opposite.hint
        end
        return nil, reason
    end
    local preview, err = prepare(buf, source, rendered(rewritten))
    if not preview then
        return nil, err
    end
    preview.command = kind.command
    return preview
end

-- Running the pending preview's own command dismisses it; any other rewrite
-- replaces it.
function M.toggle(name)
    -- Without a name this is the De Morgan toggle it was before rewrites had names.
    local kind = REWRITES[name or "de_morgan"]
    local buf = vim.api.nvim_get_current_buf()
    local shown = pending[buf]
    if shown then
        dismiss(buf)
        if shown.command == kind.command then
            return
        end
    end
    local preview, err = resolve(buf, kind)
    if not preview then
        vim.notify(err, vim.log.levels.WARN)
        return
    end
    watch(buf)
    local label = preview.column and (" [column " .. preview.column .. "] ⇒ ") or " ⇒ "
    local tail = "  " .. derivation.justification(preview.law)
    local chunks = { { label .. preview.heading .. tail, "Comment" } }
    if #preview.changed > 0 then
        chunks = {}
        local cursor, prefix = 0, label
        for _, region in ipairs(preview.changed) do
            chunks[#chunks + 1] = { prefix .. preview.heading:sub(cursor + 1, region[1]), "Comment" }
            chunks[#chunks + 1] = { preview.heading:sub(region[1] + 1, region[2]), CHANGED_GROUP }
            cursor, prefix = region[2], ""
        end
        chunks[#chunks + 1] = { preview.heading:sub(cursor + 1) .. tail, "Comment" }
    end
    preview.mark = vim.api.nvim_buf_set_extmark(buf, namespace, preview.row, 0, {
        virt_text = chunks, virt_text_pos = "eol",
    })
    preview.targets = {}
    for _, range in ipairs(preview.source and preview.consumed or {}) do
        preview.targets[#preview.targets + 1] = vim.api.nvim_buf_set_extmark(buf, TARGET, preview.row, preview.source + range[1], {
            end_col = preview.source + range[2],
            hl_group = CONSUMED_GROUP,
            priority = 4098,
        })
    end
    pending[buf] = preview
    engage(buf)
    if preview.column then
        vim.notify("Applying renames the heading; update explicit references to its old label if needed", vim.log.levels.INFO)
    end
end

-- The pending preview, provided the buffer is as it was when the preview was
-- made. Otherwise the stale state is cleared and the user is told.
local function current(buf)
    local preview = pending[buf]
    if not preview or preview.tick ~= vim.api.nvim_buf_get_changedtick(buf) then
        dismiss(buf)
        vim.notify("No current preview; run a rewrite command first", vim.log.levels.WARN)
        return nil
    end
    return preview
end

-- A region of the expression that starts at byte `start` of `row`, as one
-- mark of an editor patch. The consumed terms sit above whatever an earlier
-- step lit on their line.
local function annotation(row, start, range, group)
    if start == nil or range == nil then
        return nil
    end
    return {
        row = row, column = start + range[1], end_row = row,
        end_column = start + range[2], group = group,
        priority = group == CONSUMED_GROUP and 4097 or 4096,
    }
end

-- Anything that wants to follow a written rewrite: the buffer, the row it
-- was written to (from one) and whether it is a step below its source or
-- in its place. The plugin's own listener aligns the derivation's bars.
local function written(buf, row, kind)
    vim.api.nvim_exec_autocmds("User", {
        pattern = "TruthTableRewrite",
        data = { buf = buf, row = row, kind = kind },
    })
end

local function write_in_place(buf, preview)
    local additions = {}
    for _, range in ipairs(preview.changed) do
        local mark = annotation(preview.row, preview.written, range, CHANGED_GROUP)
        if mark then
            additions[#additions + 1] = mark
        end
    end
    edit.apply(buf, edit.prepare(buf, { row = preview.row, replacement = preview.replacement, additions = additions }))
    written(buf, preview.row + 1, "in_place")
end

local function write_step(win, preview)
    local buf = vim.api.nvim_win_get_buf(win)
    local additions = {}
    for _, range in ipairs(preview.consumed) do
        local mark = annotation(preview.row, preview.source, range, CONSUMED_GROUP)
        if mark then
            additions[#additions + 1] = mark
        end
    end
    for _, range in ipairs(preview.changed) do
        local mark = annotation(preview.row + 1, preview.step_column, range, CHANGED_GROUP)
        if mark then
            additions[#additions + 1] = mark
        end
    end
    edit.apply(buf, edit.prepare(buf, { row = preview.row, replacement = preview.step, inserted = true, additions = additions }))
    written(buf, preview.row + 2, "step")
    vim.api.nvim_win_set_cursor(win, { preview.row + 2, preview.step_column })
end

function M.apply()
    local buf = vim.api.nvim_get_current_buf()
    local preview = current(buf)
    if not preview then
        return
    end
    -- Clear state before editing so the attachment cannot invalidate a new mark.
    dismiss(buf)
    write_in_place(buf, preview)
end

-- Insert the rewritten expression as the next line of a derivation and leave
-- the cursor on it, ready for the next rewrite.
function M.apply_step()
    local buf = vim.api.nvim_get_current_buf()
    local preview = current(buf)
    if not preview then
        return
    end
    if not preview.step then
        vim.notify("Steps apply to expression lines; use :TruthTableApply for a heading", vim.log.levels.WARN)
        return
    end
    dismiss(buf)
    write_step(0, preview)
end

-- List every rewrite of the expression the cursor selects, and write the one
-- picked: below, as the next step of a derivation, or over a heading, which
-- has no steps. The menu lists each result with its law, the bars in one
-- column, as the steps of a derivation read.
function M.choose()
    local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
    dismiss(buf)
    local source, ast = source_at(buf)
    if not source then
        vim.notify(ast, vim.log.levels.WARN)
        return
    end
    local moves = rewrite.moves(ast)
    if #moves == 0 then
        vim.notify("No rewrite applies to " .. source.expression, vim.log.levels.WARN)
        return
    end
    local widest = 0
    for _, move in ipairs(moves) do
        widest = math.max(widest, vim.fn.strdisplaywidth(move.text))
    end
    local tick = vim.api.nvim_buf_get_changedtick(buf)
    vim.ui.select(moves, {
        prompt = "Rewrites of " .. source.expression,
        kind = "truth-table.rewrite",
        format_item = function(move)
            local pad = widest - vim.fn.strdisplaywidth(move.text) + 2
            return move.text .. string.rep(" ", pad) .. derivation.justification(move.law)
        end,
    }, function(move)
        if not move then
            return
        end
        -- A select UI may call back long after the menu opened.
        local shown = vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf
        if not shown or vim.api.nvim_buf_get_changedtick(buf) ~= tick then
            vim.notify("The buffer changed while the menu was open; nothing was written", vim.log.levels.WARN)
            return
        end
        local preview, err = prepare(buf, source, rendered(move.rewritten))
        if not preview then
            vim.notify(err, vim.log.levels.WARN)
        elseif preview.step then
            write_step(win, preview)
        else
            write_in_place(buf, preview)
            vim.notify("Renamed the heading; update explicit references to its old label if needed", vim.log.levels.INFO)
        end
    end)
end

return M
