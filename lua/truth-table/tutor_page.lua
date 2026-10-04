-- The tutorial's lesson pane as text. A course is a list of lessons, each
-- { title, aim, steps }; a step is { text, template, expect, note, solution },
-- where the prose and the buffer contents are block strings as a lesson file
-- writes them. Pure string handling: tutor.lua owns the windows.
local M = {}

-- A block string as a list of lines, without the newlines that close it.
function M.lines(block)
    local lines = {}
    for line in ((block or ""):gsub("\n+$", "") .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end
    if #lines == 1 and lines[1] == "" then
        return {}
    end
    return lines
end

-- Lesson files wrap their prose at a fixed width, and the pane is whatever
-- width the reader's window has. Each paragraph and each list item becomes
-- one line, for the window to wrap; fenced blocks, indented commands, table
-- rows and headings stay as written.
function M.reflow(lines)
    local out, fenced, open = {}, false, false
    for _, line in ipairs(lines) do
        if line:match("^%s*```") then
            fenced = not fenced
            out[#out + 1], open = line, false
        elseif fenced or line == "" or line:match("^    ") or line:match("^[|#]") then
            out[#out + 1], open = line, false
        elseif open and not line:match("^%- ") then
            out[#out] = out[#out] .. " " .. line:gsub("^%s+", "")
        else
            out[#out + 1], open = line, true
        end
    end
    return out
end

local function append(out, lines)
    for _, line in ipairs(lines) do
        out[#out + 1] = line
    end
end

-- The pane for one step: where the reader is, the lesson's aim, the step's
-- instructions, what the scratch pane should hold afterwards, and any remark
-- on that result.
function M.render(course, lesson_index, step_index)
    local lesson = course[lesson_index]
    local step = lesson.steps[step_index]
    local out = {
        ("# %d. %s"):format(lesson_index, lesson.title),
        "",
        ("Lesson %d of %d, step %d of %d"):format(lesson_index, #course, step_index, #lesson.steps),
        "",
        "**Aim:** " .. lesson.aim,
        "",
    }
    append(out, M.reflow(M.lines(step.text)))
    if step.expect then
        append(out, { "", "You should see:", "", "```text" })
        append(out, M.lines(step.expect))
        append(out, { "```" })
    end
    if step.note then
        append(out, { "" })
        append(out, M.reflow(M.lines(step.note)))
    end
    append(out, { "", "---", "", "`]]` next step, `[[` previous step" })
    return out
end

return M
