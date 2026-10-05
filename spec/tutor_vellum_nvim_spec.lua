-- The lesson pane is styled through vellum.nvim when that is installed, and
-- shows the step's Markdown when it is absent or cannot do the job. Three
-- vellums take turns: none, the installed one when TRUTH_TABLE_TEST_VELLUM
-- names its directory, and a stand-in whose behaviour the cases choose. A
-- vellum in package.loaded answers every later render, so each group installs
-- its own modules and restores them afterward.
-- Runs inside Neovim (make test-nvim): busted with nlua as its interpreter.
vim.opt.rtp:append(vim.fn.getcwd())
vim.o.columns = 160
vim.o.number = true
require("truth-table").setup()
local page = require("truth-table.tutor_page")
local styled = require("truth-table.tutor_vellum")

local warnings = {}
vim.notify = function(message, level)
    if level == vim.log.levels.WARN then
        warnings[#warnings + 1] = message
    end
end

local files = vim.fn.glob(vim.fn.getcwd() .. "/tutor/truth-table/*.lua", true, true)
table.sort(files)
local course = vim.tbl_map(dofile, files)

describe("the lesson pane with no vellum", function()
    local saved = {}
    setup(function()
        warnings = {}
        for _, name in ipairs({ "vellum.render", "vellum.theme" }) do
            saved[name] = { loaded = package.loaded[name], preload = package.preload[name] }
            package.loaded[name] = nil
            package.preload[name] = function() error("vellum intentionally absent") end
        end
    end)
    teardown(function()
        for name, module in pairs(saved) do
            package.loaded[name], package.preload[name] = module.loaded, module.preload
        end
    end)

    it("has nothing to show, and nothing to say about it", function()
        -- Parenthesised: a second return value would be read as the message.
        assert.is_nil((styled.render({ "# A heading" }, 80)))
        assert.are.equal(0, #warnings)
    end)
end)

describe("the lesson pane with the installed vellum", function()
    local installed = vim.env.TRUTH_TABLE_TEST_VELLUM
    if not installed then
        pending("renders every step at three widths (set TRUTH_TABLE_TEST_VELLUM to its directory)")
        return
    end

    local function alnum(lines)
        return (table.concat(lines, "\n"):gsub("[^%w]", ""))
    end

    setup(function()
        warnings = {}
        styled.restyle()
        vim.opt.rtp:append(vim.fn.expand(installed))
        vim.o.termguicolors = true
    end)

    -- The stand-in takes this vellum's place next, and its theme has to be
    -- asked for afresh.
    teardown(function()
        package.loaded["vellum.render"], package.loaded["vellum.theme"] = nil, nil
        styled.restyle()
    end)

    -- Each mark is checked against its line as it is read, so a render that
    -- comes back at all has every mark inside its line.
    for _, width in ipairs({ 104, 70, 50 }) do
        it(("renders every step with marks at width %d, and no letter or digit goes missing"):format(width), function()
            for number, lesson in ipairs(course) do
                for index in ipairs(lesson.steps) do
                    local label = ("lesson %d step %d at width %d"):format(number, index, width)
                    local markdown = page.render(course, number, index)
                    local lines, marks = styled.render(markdown, width)
                    assert.is_truthy(lines, label .. ": " .. table.concat(warnings, "; "))
                    assert.is_true(#marks > 0, label .. ": " .. table.concat(warnings, "; "))
                    assert.are.equal(alnum(markdown), alnum(lines), label .. ": text went missing")
                end
            end
        end)
    end

    it("warns nothing along the way", function()
        assert.are.equal(0, #warnings)
    end)
end)

-- The stand-in: a page that names the width it was asked for, then the
-- step's first line with its opening word marked. `behaviour` picks a
-- renderer that works, one that raises, and one whose mark runs past its line.
-- The continuous renderer lifecycle is one case, so its transitions always
-- run together, including when tests are filtered or shuffled.
describe("the lesson pane with a stand-in vellum", function()
    local behaviour = "works"
    local calls = { apply = 0, reset = 0 }

    local saved
    setup(function()
        saved = { render = package.loaded["vellum.render"], theme = package.loaded["vellum.theme"] }
        warnings = {}
        styled.restyle()
        package.loaded["vellum.theme"] = {
            apply = function()
                calls.apply = calls.apply + 1
            end,
        }
        package.loaded["vellum.render"] = {
            reset = function()
                calls.reset = calls.reset + 1
            end,
            render = function(buf, width, max_width)
                if behaviour == "raises" then
                    error("the renderer changed")
                end
                local title = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
                local lines = { "", ("  width %d of %d"):format(width, max_width), "  " .. title }
                local rows = { {}, {}, { { 0, behaviour == "astray" and 999 or 4, "Title", 100 } } }
                return lines, rows, 2, {}
            end,
        }
    end)

    teardown(function()
        package.loaded["vellum.render"], package.loaded["vellum.theme"] = saved.render, saved.theme
        styled.restyle()
    end)

    local function pane(role)
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.w[win].truth_table_tutor == role then
                return win, vim.api.nvim_win_get_buf(win)
            end
        end
    end

    local function marks()
        local _, buf = pane("lesson")
        local namespace = vim.api.nvim_get_namespaces().truth_table_tutor
        return vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, { details = true })
    end

    -- The lesson pane holds the stand-in's page for this step, wrapped to the
    -- pane's width and marked, with no gutter; the scratch pane keeps the
    -- reader's line numbers.
    local function styled_at(lesson, step)
        local win, buf = pane("lesson")
        local width = vim.api.nvim_win_get_width(win)
        local expected = { "", ("  width %d of 100"):format(width), "  " .. page.render(course, lesson, step)[1] }
        assert.are.same(expected, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
        local found = marks()
        assert.are.equal(1, #found, "marks in the pane")
        assert.are.equal(2, found[1][2], "the mark's row")
        assert.are.equal(2, found[1][3], "the mark's column")
        assert.are.equal(6, found[1][4].end_col, "the mark's end column")
        assert.are.equal("Title", found[1][4].hl_group)
        assert.are.equal(100, found[1][4].priority, "the mark's priority")
        assert.are.equal("truth-table-tutor", vim.bo[buf].filetype)
        assert.is_false(vim.bo[buf].modifiable, "lesson pane modifiable")
        assert.is_false(vim.wo[win].wrap, "lesson pane wrap")
        assert.is_false(vim.wo[win].number, "lesson pane number")
        assert.are.equal("no", vim.wo[win].signcolumn)
        assert.is_true(vim.wo[(pane("scratch"))].number, "scratch pane number")
    end

    -- The lesson pane holds the step's Markdown, as it does with no vellum.
    local function markdown_at(lesson, step)
        local win, buf = pane("lesson")
        assert.are.same(page.render(course, lesson, step), vim.api.nvim_buf_get_lines(buf, 0, -1, false))
        assert.are.equal(0, #marks(), "marks in the pane")
        assert.are.equal("markdown", vim.bo[buf].filetype)
        assert.is_false(vim.bo[buf].modifiable, "lesson pane modifiable")
        assert.is_true(vim.wo[win].wrap, "lesson pane wrap")
        assert.is_true(vim.wo[win].linebreak, "lesson pane linebreak")
    end

    it("styles, navigates, resizes and recovers from renderer failures in one session", function()
        -- opens the tutor on the stand-in's page, asking for the theme once.
        vim.cmd("TruthTableTutor")
        styled_at(1, 1)
        assert.are.equal(1, calls.apply)
        assert.are.equal(1, calls.reset)

        -- leaves the scratch pane as Markdown.
        assert.are.equal("markdown", vim.bo[select(2, pane("scratch"))].filetype)

        -- takes the keys from the styled pane, and reuses the theme on a step change.
        vim.api.nvim_set_current_win((pane("lesson")))
        vim.cmd("normal ]]")
        styled_at(2, 1)
        assert.are.equal(1, calls.apply)

        -- styles the lesson a jump lands on.
        vim.cmd("TruthTableTutor 5")
        styled_at(5, 1)

        -- wraps the page again at a new width, and keeps the reader's place in it.
        do
            local lesson_win = pane("lesson")
            vim.api.nvim_win_set_cursor(lesson_win, { 3, 0 })
            vim.api.nvim_win_set_width(lesson_win, 40)
            vim.api.nvim_exec_autocmds("WinResized", {})
            styled_at(5, 1)
            assert.are.equal(40, vim.api.nvim_win_get_width(lesson_win))
            assert.are.equal(3, vim.api.nvim_win_get_cursor(lesson_win)[1])
        end

        -- leaves the pane alone when the width is the same.
        do
            local tick = vim.api.nvim_buf_get_changedtick(select(2, pane("lesson")))
            vim.api.nvim_exec_autocmds("WinResized", {})
            assert.are.equal(tick, vim.api.nvim_buf_get_changedtick(select(2, pane("lesson"))))
        end

        -- has the groups defined again after a colorscheme.
        vim.api.nvim_exec_autocmds("ColorScheme", {})
        styled_at(5, 1)
        assert.are.equal(2, calls.apply)
        assert.are.equal(2, calls.reset)

        -- shows Markdown when the renderer raises, and says why.
        behaviour = "raises"
        vim.cmd("TruthTableTutorNext")
        markdown_at(5, 2)
        assert.are.equal(1, #warnings)
        assert.is_truthy(warnings[1]:find("vellum.nvim could not render", 1, true), warnings[1])
        assert.is_truthy(warnings[1]:find("the renderer changed", 1, true), warnings[1])

        -- says why once, however many steps the renderer goes on raising for.
        vim.cmd("TruthTableTutorPrev")
        markdown_at(5, 1)
        assert.are.equal(1, #warnings)
        vim.cmd("normal ]]")
        markdown_at(5, 2)

        -- has nothing to redo on a width change while the pane shows Markdown.
        do
            local tick = vim.api.nvim_buf_get_changedtick(select(2, pane("lesson")))
            vim.api.nvim_win_set_width((pane("lesson")), 60)
            vim.api.nvim_exec_autocmds("WinResized", {})
            assert.are.equal(tick, vim.api.nvim_buf_get_changedtick(select(2, pane("lesson"))))
        end

        -- refuses whole a page with a mark that runs past its line.
        behaviour = "astray"
        vim.cmd("TruthTableTutorNext")
        markdown_at(5, 3)

        -- uses again a renderer that works again.
        behaviour = "works"
        vim.cmd("TruthTableTutorNext")
        styled_at(5, 4)

        -- leaves no watcher behind on starting over.
        vim.cmd("TruthTableTutor!")
        styled_at(1, 1)
        assert.are.equal(2, #vim.api.nvim_get_autocmds({ group = "truth_table_tutor" }))
    end)
end)
