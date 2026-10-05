-- Editor-only preview state. The source buffer remains unchanged until apply,
-- or until a rewrite is picked from the menu of them.
local predicate = require("truth-table.predicate")
local markdown = require("truth-table.markdown")
local derivation = require("truth-table.derivation")
local rewrite = require("truth-table.rewrite")
local M = {}
local namespace = vim.api.nvim_create_namespace("truth-table.preview")
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

local function dismiss(buf)
    pending[buf] = nil
    vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
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
                vim.schedule(function()
                    if vim.api.nvim_buf_is_valid(buf) then
                        pcall(vim.api.nvim_buf_del_extmark, buf, namespace, preview.mark)
                    end
                end)
            end
        end,
        on_detach = function()
            attached[buf], pending[buf] = nil, nil
        end,
    })
end

-- A source is the expression the cursor selects plus the ways to write a
-- rewritten one, { text, law }, back: `replace(rewritten)` gives the edited
-- line, and `step(rewritten)`, for expression lines only, gives the line to
-- insert below. `offset` is the cursor's byte within the expression, when it
-- has one.

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
    local offset
    if at.row == bounds.start_line then
        local first, last = markdown.heading_cell(heading_line, column)
        -- An escaped heading does not map byte for byte (nor does it parse).
        if first and heading_line:sub(first, last) == expression then
            offset = at.byte - first + 1
        end
    end
    return {
        row = bounds.start_line,
        column = column,
        expression = expression,
        offset = offset,
        replace = function(rewritten)
            return markdown.replace_heading(heading_line, column, rewritten.text)
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
        offset = at.byte - side.first + 1,
        replace = function(rewritten)
            return derivation.replace(line, side, rewritten)
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

-- What writing `rewritten`, { text, law }, back to its source would put in
-- the buffer, as it stands now.
local function prepare(buf, source, rewritten)
    local replacement, err = source.replace(rewritten)
    if not replacement then
        return nil, err
    end
    local preview = {
        row = source.row - 1,
        replacement = replacement,
        heading = rewritten.text,
        law = rewritten.law,
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
    -- On success the second value is the law; on refusal, the reason.
    local tree, law = kind.run(ast, source.offset)
    if not tree then
        -- Factor and Distribute are one law used from either side, and easy
        -- to reach for the wrong way round: say so when the other applies.
        local opposite = kind.opposite
        if opposite and REWRITES[opposite.name].run(ast, source.offset) then
            return nil, law .. "; " .. opposite.hint
        end
        return nil, law
    end
    local preview, err = prepare(buf, source, { text = predicate.ast_to_heading(tree), law = law })
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
    local shown_text = label .. preview.heading .. "  " .. derivation.justification(preview.law)
    preview.mark = vim.api.nvim_buf_set_extmark(buf, namespace, preview.row, 0, {
        virt_text = { { shown_text, "Comment" } }, virt_text_pos = "eol",
    })
    pending[buf] = preview
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

local function write_in_place(buf, preview)
    vim.api.nvim_buf_set_lines(buf, preview.row, preview.row + 1, false, { preview.replacement })
end

-- Insert the step below the line it follows from, and put the window's
-- cursor on its expression.
local function write_step(win, preview)
    local buf = vim.api.nvim_win_get_buf(win)
    vim.api.nvim_buf_set_lines(buf, preview.row + 1, preview.row + 1, false, { preview.step })
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
        local preview, err = prepare(buf, source, move)
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
