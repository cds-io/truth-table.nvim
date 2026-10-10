-- The help's command examples, replayed: every fenced block in
-- doc/truth-table.txt that opens with a :TruthTable command and holds a
-- blank line is a before-and-after. The command line (or lines) come
-- first, then the before, with a line of ^ runs under the line the cursor
-- sits on marking every range it may be in, a blank line, and the after:
-- the buffer as it reads afterwards, a pending preview's virtual text at
-- the end of its line, the equivalence toggle's mark line below its own,
-- and a final `» message` line for what is notified.
-- Each range is tried at both ends. Runs inside Neovim (make test-nvim).
vim.opt.rtp:append(vim.fn.getcwd())
require("truth-table").setup()

local ns = vim.api.nvim_get_namespaces()["truth-table.preview"]
local HELP = "doc/truth-table.txt"

-- The commands the help describes in prose only: a picker, and the three
-- that move the tutor.
local EXEMPT =
    { TruthTableRewrites = true, TruthTableTutor = true, TruthTableTutorNext = true, TruthTableTutorPrev = true }

-- Every fenced block of the help, dedented, with the line it starts on.
local function fences()
    local found, open = {}, nil
    for number, line in ipairs(vim.fn.readfile(HELP)) do
        if open then
            if line:match("^<") then
                found[#found + 1] = open
                open = nil
            else
                open.lines[#open.lines + 1] = line
            end
        elseif line:match(">%s*$") then
            open = { at = number + 1, lines = {} }
        end
    end
    for _, fence in ipairs(found) do
        -- The help leaves a blank line after > and before <.
        while fence.lines[1] == "" do
            table.remove(fence.lines, 1)
            fence.at = fence.at + 1
        end
        while fence.lines[#fence.lines] == "" do
            fence.lines[#fence.lines] = nil
        end
        local indent = math.huge
        for _, line in ipairs(fence.lines) do
            if line:match("%S") then
                indent = math.min(indent, #line:match("^%s*"))
            end
        end
        fence.lines = vim.tbl_map(function(line)
            return line:sub(indent + 1)
        end, fence.lines)
    end
    return found
end

-- The examples: each as { at, commands, before, row, ranges, after, message }.
-- `row` is the before line the cursor sits on (from one) and `ranges` the
-- character columns (from zero) each ^ run covers.
local function examples()
    local found = {}
    for _, fence in ipairs(fences()) do
        local blank
        for index, line in ipairs(fence.lines) do
            if line == "" then
                blank = blank or index
            end
        end
        -- A range form (:.TruthTable) is a command line too.
        if fence.lines[1]:match("^:%S*TruthTable") and blank then
            local example = { at = fence.at, commands = {}, before = {}, ranges = {}, after = {} }
            local index = 1
            while fence.lines[index]:match("^:") do
                example.commands[#example.commands + 1] = fence.lines[index]:sub(2)
                index = index + 1
            end
            for i = index, blank - 1 do
                local line = fence.lines[i]
                if line:match("^[ ^]*$") and line:find("^", 1, true) then
                    assert(#example.before > 0, HELP .. ":" .. fence.at .. ": a cursor line with no line above it")
                    example.row = #example.before
                    local from = 1
                    while true do
                        local first, last = line:find("%^+", from)
                        if not first then
                            break
                        end
                        example.ranges[#example.ranges + 1] = { first - 1, last - 1 }
                        from = last + 1
                    end
                else
                    example.before[#example.before + 1] = line
                end
            end
            for i = blank + 1, #fence.lines do
                local line = fence.lines[i]
                if i == #fence.lines and line:match("^» ") then
                    example.message = line:sub(#"» " + 1)
                else
                    example.after[#example.after + 1] = line
                end
            end
            found[#found + 1] = example
        end
    end
    return found
end

-- The buffer as the help shows it: its lines, with a pending preview's
-- virtual text at the end of the line it belongs to, and the equivalence
-- toggle's mark line below the line its extmark sits on. The equivalence
-- namespace exists once the toggle has run, so it is looked up per call.
local function shown()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local mark = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })[1]
    if mark then
        local parts = {}
        for _, chunk in ipairs(mark[4].virt_text) do
            parts[#parts + 1] = chunk[1]
        end
        lines[mark[2] + 1] = lines[mark[2] + 1] .. table.concat(parts)
    end
    local equivalence = vim.api.nvim_get_namespaces()["truth-table.equivalence"]
    if equivalence then
        local marks = vim.api.nvim_buf_get_extmarks(0, equivalence, 0, -1, { details = true })
        for i = #marks, 1, -1 do
            local below = marks[i]
            for j = #below[4].virt_lines, 1, -1 do
                local parts = {}
                for _, chunk in ipairs(below[4].virt_lines[j]) do
                    parts[#parts + 1] = chunk[1]
                end
                table.insert(lines, below[2] + 2, table.concat(parts))
            end
        end
    end
    return lines
end

local notified
vim.notify = function(message)
    notified = message
end

local function replay(example, column)
    -- The equivalence switch is global and on by default, and a toggle in
    -- one replay would carry into the next; every example starts from
    -- off, so the toggle example enables the marks and no other example
    -- paints them. (Autocmds do not fire here anyway: the marks an
    -- example shows come from the command's own refresh.)
    require("truth-table.equivalence").set(false)
    vim.cmd("enew!")
    notified = nil
    vim.api.nvim_buf_set_lines(0, 0, -1, false, example.before)
    local row = example.row or 1
    local line = example.before[row] or ""
    vim.api.nvim_win_set_cursor(0, { row, math.max(0, vim.fn.byteidx(line, column)) })
    for _, command in ipairs(example.commands) do
        vim.cmd(command)
    end
end

-- The command a command line names, without its range, bang or argument.
local function named(command)
    return command:match("(TruthTable%w*)")
end

describe("the help's command examples", function()
    local found = examples()

    it("exist, so the help has at least one block per command", function()
        assert.is_true(#found >= 20, "found " .. #found)
    end)

    it("cover every user command, but the picker and the tutor's", function()
        local shown_in = {}
        for _, example in ipairs(found) do
            for _, command in ipairs(example.commands) do
                shown_in[named(command)] = true
            end
        end
        for name in pairs(vim.api.nvim_get_commands({})) do
            if name:match("^TruthTable") and not EXEMPT[name] then
                assert.is_true(shown_in[name] == true, name .. " has no before-and-after block in " .. HELP)
            end
        end
    end)

    for _, example in ipairs(found) do
        local label = ("%s:%d %s"):format(HELP, example.at, example.commands[1])
        it("replays " .. label, function()
            local columns = {}
            for _, range in ipairs(example.ranges) do
                columns[#columns + 1] = range[1]
                columns[#columns + 1] = range[2]
            end
            if #columns == 0 then
                columns[1] = 0
            end
            for _, column in ipairs(columns) do
                replay(example, column)
                local where = label .. " with the cursor at column " .. column
                assert.are.same(example.after, shown(), where)
                if example.message then
                    assert.are.equal(example.message, notified, where)
                else
                    assert.is_nil(notified, where .. " notified: " .. tostring(notified))
                end
            end
        end)
    end
end)
