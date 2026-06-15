-- Unit tests for truth-table.core. These run under a bare Lua interpreter via
-- busted (`busted` from the project root): core has no Neovim dependency. The
-- vim-coupled layer (init.lua: buffer scanning, commands, keymaps) is exercised
-- by hand / integration, not here.

local core = require("truth-table.core")

-- Helper: parse + evaluate a predicate against a context, the way expand does.
local function eval(expr, ctx)
    local tokens = assert(core.tokenize(expr))
    local ast = assert(core.parse_predicate(tokens))
    return core.eval_ast(ast, ctx)
end

describe("core.display_width (pure default)", function()
    it("counts ASCII as one column each", function()
        assert.are.equal(3, core.display_width("abc"))
        assert.are.equal(0, core.display_width(""))
    end)

    it("counts a multibyte codepoint as one column", function()
        -- The logic symbols are 3 UTF-8 bytes but one display column.
        assert.are.equal(1, core.display_width("∧"))
        assert.are.equal(5, core.display_width("A ∧ B"))
    end)
end)

describe("core.center_pad", function()
    it("centers within the width", function()
        assert.are.equal(" x ", core.center_pad("x", 3))
        assert.are.equal("ab", core.center_pad("ab", 2))
    end)

    it("biases the extra space to the right on odd padding", function()
        assert.are.equal("x ", core.center_pad("x", 2))
    end)
end)

describe("core.generate_rows", function()
    it("produces 2^n rows, MSB-first", function()
        assert.are.same({ { "0" }, { "1" } }, core.generate_rows(1))
        assert.are.same({
            { "0", "0" },
            { "0", "1" },
            { "1", "0" },
            { "1", "1" },
        }, core.generate_rows(2))
    end)
end)

describe("core.parse_truth_table_args", function()
    it("expands an integer N into A, B, C, ... headers", function()
        assert.are.same({ "A", "B", "C" }, core.parse_truth_table_args("3"))
        assert.are.same({ "A" }, core.parse_truth_table_args("1"))
    end)

    it("accepts explicit variable names", function()
        assert.are.same({ "p", "q", "r" }, core.parse_truth_table_args("p q r"))
    end)

    it("rejects out-of-range N", function()
        assert.is_nil(core.parse_truth_table_args("0"))
        assert.is_nil(core.parse_truth_table_args("11"))
    end)

    it("rejects empty input, bad names, and duplicates", function()
        assert.is_nil(core.parse_truth_table_args(""))
        assert.is_nil(core.parse_truth_table_args("1bad"))
        assert.is_nil(core.parse_truth_table_args("p p"))
    end)

    it("returns an error message alongside nil", function()
        local headers, err = core.parse_truth_table_args("")
        assert.is_nil(headers)
        assert.is_truthy(err:match("Usage"))
    end)
end)

describe("core table-line recognition", function()
    it("recognizes table and separator lines", function()
        assert.is_true(core.is_table_line("| A | B |"))
        assert.is_true(core.is_table_line("  |x|  "))
        assert.is_false(core.is_table_line("not a table"))
    end)

    it("recognizes separator rows with optional colons", function()
        assert.is_true(core.is_separator("|:---:|:---:|"))
        assert.is_true(core.is_separator("| --- | --- |"))
        assert.is_false(core.is_separator("| A | B |"))
    end)

    it("splits a row into trimmed cells", function()
        assert.are.same({ "A", "B", "C" }, core.split_row("|  A | B  |  C |"))
    end)
end)

describe("core.parse_table_lines", function()
    it("separates headers from data rows (skipping the separator)", function()
        local tbl = core.parse_table_lines({
            "| A | B |",
            "|:-:|:-:|",
            "| 0 | 1 |",
            "| 1 | 0 |",
        })
        assert.are.same({ "A", "B" }, tbl.headers)
        assert.are.same({ { "0", "1" }, { "1", "0" } }, tbl.rows)
    end)
end)

describe("core.tokenize", function()
    it("recognizes idents, operators, parens, and literals", function()
        local toks = assert(core.tokenize("A and !B"))
        assert.are.same({ type = "ident", value = "A" }, toks[1])
        assert.are.same({ type = "op", value = "and" }, toks[2])
        assert.are.same({ type = "op", value = "!" }, toks[3])
        assert.are.same({ type = "ident", value = "B" }, toks[4])
    end)

    it("maps -> to implies", function()
        local toks = assert(core.tokenize("A -> B"))
        assert.are.same({ type = "op", value = "implies" }, toks[2])
    end)

    it("errors on an unexpected character", function()
        local toks, err = core.tokenize("A & B")
        assert.is_nil(toks)
        assert.is_truthy(err:match("Unexpected character"))
    end)
end)

describe("predicate parsing + evaluation", function()
    it("evaluates and / or / not", function()
        assert.are.equal(1, eval("A and B", { A = 1, B = 1 }))
        assert.are.equal(0, eval("A and B", { A = 1, B = 0 }))
        assert.are.equal(1, eval("A or B", { A = 0, B = 1 }))
        assert.are.equal(1, eval("!A", { A = 0 }))
        assert.are.equal(0, eval("not A", { A = 1 }))
    end)

    it("evaluates xor and implies", function()
        assert.are.equal(1, eval("A xor B", { A = 1, B = 0 }))
        assert.are.equal(0, eval("A xor B", { A = 1, B = 1 }))
        assert.are.equal(0, eval("A -> B", { A = 1, B = 0 }))
        assert.are.equal(1, eval("A -> B", { A = 0, B = 0 }))
    end)

    it("honors precedence: and binds tighter than or", function()
        -- A or (B and C): with A=1 the result is 1 regardless of B,C.
        assert.are.equal(1, eval("A or B and C", { A = 1, B = 0, C = 0 }))
        -- (A and B) is 0, so result follows C via or.
        assert.are.equal(0, eval("A and B or C", { A = 1, B = 0, C = 0 }))
    end)

    it("honors parentheses overriding precedence", function()
        assert.are.equal(0, eval("(A or B) and C", { A = 1, B = 0, C = 0 }))
    end)

    it("evaluates literals", function()
        assert.are.equal(1, eval("1 or A", { A = 0 }))
        assert.are.equal(0, eval("0 and A", { A = 1 }))
    end)

    it("reports a parse error on trailing tokens", function()
        local toks = assert(core.tokenize("A B"))
        local ast, err = core.parse_predicate(toks)
        assert.is_nil(ast)
        assert.is_truthy(err:match("Unexpected token after expression"))
    end)

    it("reports a parse error on an unclosed paren", function()
        local toks = assert(core.tokenize("(A and B"))
        local ast, err = core.parse_predicate(toks)
        assert.is_nil(ast)
        assert.is_truthy(err)
    end)
end)

describe("core.validate_vars", function()
    local header_set = { A = true, B = true }

    it("passes when all vars are known", function()
        local ast = assert(core.parse_predicate(assert(core.tokenize("A and B"))))
        assert.is_nil(core.validate_vars(ast, header_set))
    end)

    it("flags an unknown column", function()
        local ast = assert(core.parse_predicate(assert(core.tokenize("A and Z"))))
        local err = core.validate_vars(ast, header_set)
        assert.is_truthy(err and err:match("Unknown column: Z"))
    end)
end)

describe("core.ast_to_heading", function()
    it("renders operators with their symbols", function()
        local function heading(expr)
            return core.ast_to_heading(assert(core.parse_predicate(assert(core.tokenize(expr)))))
        end
        assert.are.equal("A ∧ B", heading("A and B"))
        assert.are.equal("A ∨ B", heading("A or B"))
        assert.are.equal("A ⊕ B", heading("A xor B"))
        assert.are.equal("¬A", heading("!A"))
        assert.are.equal("A → B", heading("A -> B"))
        assert.are.equal("(A ∨ B) ∧ C", heading("(A or B) and C"))
    end)
end)

describe("core.expand", function()
    local tbl = {
        headers = { "A", "B" },
        rows = { { "0", "0" }, { "0", "1" }, { "1", "0" }, { "1", "1" } },
    }

    it("appends a computed column per predicate", function()
        local headers, rows = core.expand(tbl, { "A and B" })
        assert.are.same({ "A", "B", "A ∧ B" }, headers)
        assert.are.same({
            { "0", "0", "0" },
            { "0", "1", "0" },
            { "1", "0", "0" },
            { "1", "1", "1" },
        }, rows)
    end)

    it("supports multiple predicates", function()
        local headers = core.expand(tbl, { "A or B", "A xor B" })
        assert.are.same({ "A", "B", "A ∨ B", "A ⊕ B" }, headers)
    end)

    it("returns nil + message for an unknown column", function()
        local headers, err = core.expand(tbl, { "A and Z" })
        assert.is_nil(headers)
        assert.is_truthy(err:match("Unknown column: Z"))
    end)

    it("returns nil + message for a parse error", function()
        local headers, err = core.expand(tbl, { "A &" })
        assert.is_nil(headers)
        assert.is_truthy(err:match("Parse error"))
    end)

    it("does not mutate the input table", function()
        core.expand(tbl, { "A and B" })
        assert.are.same({ "A", "B" }, tbl.headers)
        assert.are.equal(4, #tbl.rows)
        assert.are.equal(2, #tbl.rows[1])
    end)
end)

describe("core.toggle_cells", function()
    it("converts 0/1 to F/T", function()
        local rows = core.toggle_cells({ { "0", "1" }, { "1", "0" } })
        assert.are.same({ { "F", "T" }, { "T", "F" } }, rows)
    end)

    it("converts F/T back to 0/1", function()
        local rows = core.toggle_cells({ { "F", "T" }, { "T", "F" } })
        assert.are.same({ { "0", "1" }, { "1", "0" } }, rows)
    end)

    it("leaves non-boolean cells untouched", function()
        local rows = core.toggle_cells({ { "0", "x" } })
        assert.are.same({ { "F", "x" } }, rows)
    end)
end)

describe("core.format_table", function()
    it("renders a centered, aligned markdown table", function()
        local lines = core.format_table({ "A", "B" }, { { "0", "1" } })
        assert.are.same({
            "|  A  |  B  |",
            "|:---:|:---:|",
            "|  0  |  1  |",
        }, lines)
    end)

    it("widens columns to fit the widest cell", function()
        local lines = core.format_table({ "A", "long" }, { { "0", "1" } })
        -- "long" is width 4, so column 2's interior is 4 wide.
        assert.are.equal("|  A  | long |", lines[1])
        assert.are.equal("|:---:|:----:|", lines[2])
        assert.are.equal("|  0  |  1   |", lines[3])
    end)
end)
