-- The tutorial's lesson pane as text. A course is a list of lessons, each
-- { part, title, aim, steps }, where `part` names the part of the course the
-- lesson opens (the lessons after it belong to that part until the next
-- opens one, so the first lesson names one and most lessons name none); a
-- step is { text, template, expect, note, solution },
-- where the prose and the buffer contents are block strings as a lesson file
-- writes them. Inside a ```logic fenced block of `text` or `note`, and
-- anywhere in `template`, a line may colour a span with `[:colour ...]`
-- (spans.lua has the grammar): the markers come out here and the spans
-- go to lesson.lua, which paints them. Pure string handling: init.lua owns
-- the windows. The block strings become lines in text.lua; this lays a
-- step's page out of them.
local fp = require("cds.fp")
local text = require("truth-table.tutor.text")
local M = {}

M.lines, M.reflow, M.body, M.template = text.lines, text.reflow, text.body, text.template

local function append(out, lines)
    for _, line in ipairs(lines) do
        out[#out + 1] = line
    end
end

-- The part a lesson is in: its number, how many there are, and its name.
local function part_of(course, lesson_index)
    local number, count, name = 0, 0, nil
    for index, lesson in ipairs(course) do
        if lesson.part then
            count = count + 1
            if index <= lesson_index then
                number, name = count, lesson.part
            end
        end
    end
    return number, count, name
end

-- The progress bar's cells by state, each a highlight group with its default
-- link: the lessons the reader has visited, the one shown, and those ahead.
M.STATES = {
    visited = { group = "TruthTableTutorVisited", link = "DiagnosticOk" },
    current = { group = "TruthTableTutorCurrent", link = "DiagnosticWarn" },
    ahead = { group = "TruthTableTutorAhead", link = "NonText" },
}

-- The lesson pane's winbar for one step (`place` is its lesson and step): a
-- bar with a cell per lesson, coloured by state (visited means reached:
-- `furthest` is the last lesson the reader has been to), the lesson and
-- step, and the part, set to the right and the first to go when the pane
-- is too narrow for all of it. In the winbar's own format, so a `%` in a
-- part's name is doubled.
function M.progress(course, place, furthest)
    local number, count, name = part_of(course, place.lesson)
    local cells, state = {}, nil
    for index = 1, #course do
        local now = index == place.lesson and "current" or index <= furthest and "visited" or "ahead"
        if now ~= state then
            state = now
            cells[#cells + 1] = "%#" .. M.STATES[state].group .. "#"
        end
        cells[#cells + 1] = "█"
    end
    return ("%s%%* lesson %d of %d, step %d of %d %%<%%=Part %d of %d: %s"):format(
        table.concat(cells),
        place.lesson,
        #course,
        place.step,
        #course[place.lesson].steps,
        number,
        count,
        (name:gsub("%%", "%%%%"))
    )
end

-- The pane for one step (`place` is its lesson and step): the lesson's
-- title, its aim on the lesson's first step, the step's instructions, what
-- the scratch pane should hold afterwards (inline when it is one line, else
-- as a labelled panel), and any remark on that result,
-- closed by a rule; the first lesson's steps also name the keys that move.
-- The winbar carries the lesson and step, so the header repeats nothing it
-- says. The spans come back with rows into these lines. Nil and a message,
-- naming the field, for a step whose markers are wrong.
function M.render(course, place)
    local lesson = course[place.lesson]
    local step = lesson.steps[place.step]
    local out = { ("## %d. %s"):format(place.lesson, lesson.title), "" }
    if place.step == 1 then
        append(out, { "**Aim:** " .. lesson.aim, "" })
    end
    local found = {}
    local function body(field)
        local lines, marked = M.body(step[field])
        if not lines then
            return field .. ": " .. marked
        end
        local offset = #out
        append(out, lines)
        for _, span in ipairs(marked) do
            span.row = span.row + offset
            found[#found + 1] = span
        end
    end
    local err = body("text")
    if err then
        return nil, err
    end
    if step.expect then
        local expected = M.lines(step.expect)
        local marked = fp.find(expected, function(line)
            return line:find("%[:%w+")
        end)
        if marked then
            return nil, "expect: a colour span in the expected result: " .. marked
        end
        -- A one-line result reads as a sentence; a longer one is a panel
        -- labelled "result" (vellum shows a fence's info string, first word
        -- only, as the panel's label, and finds no language of that name).
        if #expected == 1 then
            append(out, { "", "You should see `" .. expected[1] .. "`." })
        else
            append(out, { "", "```result" })
            append(out, expected)
            append(out, { "```" })
        end
    end
    if step.note then
        append(out, { "" })
        err = body("note")
        if err then
            return nil, err
        end
    end
    append(out, { "", "---" })
    if place.lesson == 1 then
        append(out, { "", "`]]` next step, `[[` previous step" })
    end
    return out, found
end

-- The first thing wrong with `course`, as a message: a first lesson that
-- opens no part, or the first step whose markers are wrong, naming lesson,
-- step and field; nil when every step renders.
function M.check(course)
    if type(course[1].part) ~= "string" then
        return "lesson 1: no part"
    end
    for number, lesson in ipairs(course) do
        for index, step in ipairs(lesson.steps) do
            local lines, err = M.render(course, { lesson = number, step = index })
            if not lines then
                return ("lesson %d step %d: %s"):format(number, index, err)
            end
            local template, template_err = M.template(step.template)
            if not template then
                return ("lesson %d step %d: template: %s"):format(number, index, template_err)
            end
        end
    end
end

return M
