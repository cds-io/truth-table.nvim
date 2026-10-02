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

    it("accepts the logic symbols the headings are rendered with", function()
        local toks = assert(core.tokenize("¬A ∧ B ∨ C ⊕ D → E"))
        local ops = {}
        for _, tok in ipairs(toks) do
            if tok.type == "op" then
                ops[#ops + 1] = tok.value
            end
        end
        assert.are.same({ "not", "and", "or", "xor", "implies" }, ops)
    end)

    it("maps ⇒ to implies", function()
        local toks = assert(core.tokenize("A ⇒ B"))
        assert.are.same({ type = "op", value = "implies" }, toks[2])
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

    it("evaluates iff in each of its spellings", function()
        for _, op in ipairs({ "iff", "=", "<->", "<=>", "⇔", "↔" }) do
            assert.are.equal(1, eval("A " .. op .. " B", { A = 0, B = 0 }))
            assert.are.equal(0, eval("A " .. op .. " B", { A = 0, B = 1 }))
            assert.are.equal(0, eval("A " .. op .. " B", { A = 1, B = 0 }))
            assert.are.equal(1, eval("A " .. op .. " B", { A = 1, B = 1 }))
        end
    end)

    it("reads => as implies, and = without spaces", function()
        assert.are.equal(0, eval("A => B", { A = 1, B = 0 }))
        assert.are.equal(1, eval("A=B", { A = 0, B = 0 }))
    end)

    it("binds iff loosest of all", function()
        -- A = (B -> C), where (A = B) -> C would give 1.
        assert.are.equal(0, eval("A = B -> C", { A = 0, B = 0, C = 0 }))
        -- (A xor B) = C, where A xor (B = C) would give 1.
        assert.are.equal(0, eval("A xor B = C", { A = 1, B = 1, C = 1 }))
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
        assert.are.equal("A = B", heading("A iff B"))
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

describe("core.is_expression_input", function()
    it("treats an integer or a plain name list as the classic form", function()
        assert.is_false(core.is_expression_input("3"))
        assert.is_false(core.is_expression_input("p q r"))
    end)

    it("detects operators, symbols, parens, and separators", function()
        assert.is_true(core.is_expression_input("p and q"))
        assert.is_true(core.is_expression_input("p ∧ q"))
        assert.is_true(core.is_expression_input("!p"))
        assert.is_true(core.is_expression_input("(p)"))
        assert.is_true(core.is_expression_input("p | q"))
        assert.is_true(core.is_expression_input("p, q"))
    end)
end)

describe("core.build_truth_table", function()
    it("keeps the integer and name-list forms", function()
        local headers, rows = core.build_truth_table("2")
        assert.are.same({ "A", "B" }, headers)
        assert.are.same({ { "0", "0" }, { "0", "1" }, { "1", "0" }, { "1", "1" } }, rows)

        headers, rows = core.build_truth_table("p q r")
        assert.are.same({ "p", "q", "r" }, headers)
        assert.are.equal(8, #rows)
    end)

    it("derives the variables from |-separated expressions, in order of first appearance", function()
        local headers, rows = core.build_truth_table("(m ∧  (a ⊕ b) ∨ (¬m ∧ (a ∧ b))) | m ⊕ (a ∧ b)")
        assert.are.same({ "m", "a", "b", "(m ∧ (a ⊕ b) ∨ (¬m ∧ (a ∧ b)))", "m ⊕ (a ∧ b)" }, headers)
        assert.are.same({
            { "0", "0", "0", "0", "0" },
            { "0", "0", "1", "0", "0" },
            { "0", "1", "0", "0", "0" },
            { "0", "1", "1", "1", "1" },
            { "1", "0", "0", "0", "1" },
            { "1", "0", "1", "1", "1" },
            { "1", "1", "0", "1", "1" },
            { "1", "1", "1", "0", "0" },
        }, rows)
    end)

    it("accepts commas and the keyword operators too", function()
        local headers = core.build_truth_table("p and q, p xor r")
        assert.are.same({ "p", "q", "r", "p ∧ q", "p ⊕ r" }, headers)
    end)

    it("lets a bare variable fix the column order without adding a column", function()
        local headers = core.build_truth_table("b | a | a -> b")
        assert.are.same({ "b", "a", "a → b" }, headers)
    end)

    it("emits a repeated expression once", function()
        local headers = core.build_truth_table("a and b | a ∧ b")
        assert.are.same({ "a", "b", "a ∧ b" }, headers)
    end)

    it("returns nil + message for a parse error", function()
        local headers, err = core.build_truth_table("a and | b")
        assert.is_nil(headers)
        assert.is_truthy(err:match("Parse error"))
    end)

    it("returns nil + message when no expression names a variable", function()
        local headers, err = core.build_truth_table("1 or 0")
        assert.is_nil(headers)
        assert.is_truthy(err:match("No variables"))
    end)

    it("shows the two selector forms agree once the inner operator is iff", function()
        local headers, rows = core.build_truth_table("(m ∧ (a ⊕ b) ∨ (¬m ∧ (a=b))) | m ⊕ (a=b)")
        assert.are.same({ "m", "a", "b", "(m ∧ (a ⊕ b) ∨ (¬m ∧ (a = b)))", "m ⊕ (a = b)" }, headers)
        for _, row in ipairs(rows) do
            assert.are.equal(row[4], row[5])
        end
    end)

    it("returns nil + message past 10 variables", function()
        local headers, err = core.build_truth_table("a and b and c and d and e and f and g and h and i and j and k")
        assert.is_nil(headers)
        assert.is_truthy(err:match("Too many variables"))
    end)
end)

describe("core.args_from_lines", function()
    it("joins lines with the column delimiter, skipping blank ones", function()
        assert.are.equal("m | a  | b | m xor a | a and b", core.args_from_lines({ "m | a  | b", "  m xor a ", "", "a and b" }))
    end)

    it("feeds build_truth_table: a first line of bare variables pins the order", function()
        local args = core.args_from_lines({ "m | a  | b", "(m ∧  (a ⊕ b) ∨ (¬m ∧ (a ∧ b))) ", "m ⊕ (a ∧ b)" })
        local headers, rows = core.build_truth_table(args)
        assert.are.same({ "m", "a", "b", "(m ∧ (a ⊕ b) ∨ (¬m ∧ (a ∧ b)))", "m ⊕ (a ∧ b)" }, headers)
        assert.are.equal(8, #rows)
    end)

    it("leaves a single line as it is, so the classic forms still work", function()
        assert.are.same({ "p", "q" }, (core.build_truth_table(core.args_from_lines({ "p q" }))))
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

describe("validated table pipeline", function()
    it("expands toggled tables correctly and preserves F/T presentation", function()
        local headers, rows = core.build_truth_table("A B")
        local toggled = core.toggle_cells(rows)
        local _, expanded = core.expand({ headers = headers, rows = toggled }, { "not A", "A iff B" })
        assert.are.same({
            { "F", "F", "T", "T" }, { "F", "T", "T", "F" },
            { "T", "F", "F", "F" }, { "T", "T", "F", "T" },
        }, expanded)
        assert.are.same({ { "0", "0" }, { "0", "1" }, { "1", "0" }, { "1", "1" } }, rows)
        assert.are.same(rows, core.toggle_cells(toggled))
    end)

    it("rejects ragged rows, duplicate headings, and invalid cells", function()
        for _, tbl in ipairs({
            { headers = { "A", "B" }, rows = { { "1" } } },
            { headers = { "A" }, rows = { { "1", "0" } } },
            { headers = { "A", "A" }, rows = { { "0", "1" } } },
            { headers = { "A" }, rows = { { "x" } } },
            { headers = { "A", "B" }, rows = { { "F", "1" } } },
        }) do
            local value, err = core.expand(tbl, { "A" })
            assert.is_nil(value)
            assert.is_string(err)
        end
    end)

    it("validates the Markdown boundary before editing", function()
        assert.is_nil(core.parse_table_lines({ "|A|", "not a separator", "|0|" }))
        assert.is_nil(core.parse_table_lines({ "|A|", "|---|---|", "|0|" }))
        assert.is_nil(core.parse_table_lines({ "|A|", "|---|", "|0|1|" }))
        assert.is_nil(core.parse_table_lines({ "|A|", "|---|", "|x|" }))
    end)

    it("does not duplicate computed columns on repeated expansion", function()
        local headers, rows = core.build_truth_table("A and B")
        local h, r = core.expand({ headers = headers, rows = rows }, { "A ∧ B", "A and B" })
        assert.are.same(headers, h)
        assert.are.same(rows, r)
    end)

    it("parses each construction expression once", function()
        local original, calls = core.parse_expression, 0
        core.parse_expression = function(input)
            calls = calls + 1
            return original(input)
        end
        local ok, headers = pcall(core.build_truth_table, "A and B | not A")
        core.parse_expression = original
        assert.is_true(ok)
        assert.is_table(headers)
        assert.are.equal(2, calls)
    end)
end)

describe("result composition", function()
    local result = require("truth-table.result")
    it("preserves false and zero successes and short-circuits errors", function()
        assert.is_false(result.bind(false, nil, function(value) return value end))
        assert.are.equal(0, result.bind(0, nil, function(value) return value end))
        local value, err = result.bind(nil, "failure", function() error("must not run") end)
        assert.is_nil(value)
        assert.are.equal("failure", err)
        local calls = 0
        value, err = result.traverse({ 1, 2, 3 }, function(n)
            calls = calls + 1
            if n == 2 then return nil, "stop" end
            return n
        end)
        assert.is_nil(value)
        assert.are.equal("stop", err)
        assert.are.equal(2, calls)
    end)
end)

describe("stored column references", function()
    it("uses stored values after source columns have been dropped", function()
        local tbl = { headers = { "B", "A ∧ B" }, rows = { { "0", "0" }, { "1", "1" } } }
        local headers, rows = core.expand(tbl, { "not `A ∧ B`" })
        assert.are.same({ "B", "A ∧ B", "¬`A ∧ B`" }, headers)
        assert.are.same({ { "0", "0", "1" }, { "1", "1", "0" } }, rows)
        assert.is_nil(core.expand(tbl, { "not (A and B)" }))
    end)

    it("distinguishes a stored value from recomputing its displayed formula", function()
        local tbl = { headers = { "A", "B", "A ∧ B" }, rows = { { "1", "1", "0" } } }
        local _, rows = core.expand(tbl, { "not `A ∧ B`", "not (A and B)" })
        assert.are.same({ { "1", "1", "0", "1", "0" } }, rows)
    end)

    it("binds names to positions without mutating the parsed tree", function()
        local ast = assert(core.parse_expression("not `A ∧ B`"))
        local bound = assert(core.bind_columns(ast, { ["A ∧ B"] = 2 }))
        assert.are.equal(1, core.eval_ast(bound, { 1, 0 }))
        assert.are.equal("reference", ast.operand.type)
        assert.are.equal("column", bound.operand.type)
        assert.are.equal("¬`A ∧ B`", core.ast_to_heading(ast))
    end)

    it("round-trips reference headings and handles comma-bearing labels", function()
        local input = "not `p, q`"
        local ast = assert(core.parse_expression(input))
        local heading = core.ast_to_heading(ast)
        assert.are.same(ast, core.parse_expression(heading))
        assert.are.same({ "not `p, q`", "A" }, core.split_expressions(input .. ", A", ","))
        local _, rows = core.expand({ headers = { "p, q" }, rows = { { "T" } } }, { input })
        assert.are.same({ { "T", "F" } }, rows)
    end)

    it("rejects invalid references and references during table creation", function()
        for _, input in ipairs({ "``", "`A", "not `A" }) do
            assert.is_nil(core.parse_expression(input))
        end
        assert.is_nil(core.expand({ headers = { "A" }, rows = { { "0" } } }, { "`missing`" }))
        local headers, err = core.build_truth_table("A and `B`")
        assert.is_nil(headers)
        assert.are.equal("Column references require an existing table", err)
        for _, input in ipairs({ "A,,B", "A|", "|A", "A,`B" }) do
            assert.is_nil(core.split_expressions(input, "|,"))
        end
    end)
end)

describe("pure model edits", function()
    local model = require("truth-table.table_model")

    it("composes normalized edits while retaining F/T encoding", function()
        local original = { headers = { "A", "B" }, rows = { { "F", "T" }, { "T", "F" } } }
        local normalized = assert(model.normalize(original))
        assert.are.same(normalized, model.normalize(normalized))
        local dropped = assert(model.drop_column(normalized, 1))
        assert.are.same({ { "T" }, { "F" } }, model.render_rows(dropped))
        local remaining = assert(model.drop_row(dropped, 1))
        assert.are.same({ { "F" } }, model.render_rows(remaining))
        local toggled = assert(model.toggle(remaining))
        assert.are.same({ { "0" } }, model.render_rows(toggled))
        assert.are.same(remaining, model.toggle(toggled))
        assert.are.same({ { "F", "T" }, { "T", "F" } }, original.rows)
        assert.are.same({ { 0, 1 }, { 1, 0 } }, normalized.rows)
    end)

    it("returns fresh nested arrays without sharing input rows", function()
        local original = { headers = { "A", "B" }, rows = { { 0, 1 }, { 1, 0 } }, encoding = "tf" }
        for _, edited in ipairs({ model.drop_row(original, 1), model.drop_column(original, 1), model.toggle(original) }) do
            edited.headers[1] = "changed"
            edited.rows[1][1] = 9
        end
        assert.are.same({ headers = { "A", "B" }, rows = { { 0, 1 }, { 1, 0 } }, encoding = "tf" }, original)
    end)

    it("preserves the mode when the last data row is dropped", function()
        local empty = assert(model.drop_row({ headers = { "A" }, rows = { { "T" } } }, 1))
        assert.are.equal("tf", empty.encoding)
        assert.are.same({}, empty.rows)
        assert.are.equal("bits", assert(model.toggle(empty)).encoding)
    end)

    it("rejects invalid indices, modes, and dropping the only column", function()
        local tbl = { headers = { "A", "B" }, rows = { { "0", "1" } } }
        for _, index in ipairs({ 0, -1, 3, 1.5, "1" }) do
            assert.is_nil(model.drop_row(tbl, index))
            assert.is_nil(model.drop_column(tbl, index))
        end
        assert.is_nil(model.drop_column({ headers = { "A" }, rows = {} }, 1))
        assert.is_nil(model.normalize({ headers = { "A" }, rows = {}, encoding = "bad" }))
        assert.is_nil(model.normalize({ headers = { "A" }, rows = { { "T" } }, encoding = "bits" }))
    end)
end)

describe("semantic core pipeline", function()
    it("composes all edits using numeric cells until the Markdown boundary", function()
        local tbl = assert(core.build_model("A and B"))
        assert.are.same({ 1, 1, 1 }, tbl.rows[4])
        local toggled = assert(core.toggle_model(tbl))
        local dropped = assert(core.drop_model_column(toggled, 1))
        local expanded = assert(core.expand_model(dropped, { "not `A ∧ B`" }))
        assert.are.equal("tf", expanded.encoding)
        assert.are.same({ 1, 1, 0 }, expanded.rows[4])
        local edited = assert(core.drop_model_row(expanded, 1))
        assert.are.same(edited, core.parse_model(assert(core.format_model(edited))))
        assert.are.equal("bits", tbl.encoding)
        assert.are.same({ 1, 1, 1 }, tbl.rows[4])
    end)

    it("keeps semantic and legacy construction behavior aligned", function()
        for _, input in ipairs({ "2", "p q", "B | A | A implies B" }) do
            local semantic = assert(core.build_model(input))
            local headers, rows = core.build_truth_table(input)
            assert.are.same(headers, semantic.headers)
            assert.are.same(core.format_table(headers, rows), core.format_model(semantic))
        end
        assert.is_nil(core.build_model(""))
        local tbl = assert(core.build_model("A"))
        local expanded, err = core.expand_model(tbl, { "missing" })
        assert.is_nil(expanded)
        assert.are.equal("Unknown column: missing", err)
    end)
end)

describe("materialized column model", function()
    local model = require("truth-table.table_model")
    it("appends columns purely and deduplicates headings in one place", function()
        local tbl = { headers = { "A" }, rows = { { 0 }, { 1 } }, encoding = "tf" }
        local columns = {
            { heading = "¬A", values = { 1, 0 } },
            { heading = "¬A", values = { 1, 0 } },
            { heading = "A", values = { 0, 1 } },
        }
        local extended = assert(model.append_columns(tbl, columns))
        assert.are.same({ headers = { "A", "¬A" }, rows = { { 0, 1 }, { 1, 0 } }, encoding = "tf" }, extended)
        extended.rows[1][1] = 1
        extended.headers[1] = "changed"
        assert.are.same({ { 0 }, { 1 } }, tbl.rows)
        assert.are.same({ "A" }, tbl.headers)
        assert.are.same({ 1, 0 }, columns[1].values)
    end)

    it("rejects malformed materialized columns before returning a table", function()
        local tbl = { headers = { "A" }, rows = { { 0 }, { 1 } } }
        for _, column in ipairs({
            { heading = "B", values = { 1 } },
            { heading = "B", values = { 1, 0, 1 } },
            { heading = "B", values = { 1, 2 } },
            { heading = " B", values = { 1, 0 } },
        }) do
            local value, err = model.append_columns(tbl, { column })
            assert.is_nil(value)
            assert.is_string(err)
        end
        assert.are.same({ { 0 }, { 1 } }, tbl.rows)
    end)
end)

describe("public table shape validation", function()
    local model = require("truth-table.table_model")
    it("rejects sparse arrays and wrong types without throwing", function()
        for _, tbl in ipairs({
            false, {}, { headers = "A", rows = {} },
            { headers = { [1] = "A", [3] = "B" }, rows = {} },
            { headers = { "A" }, rows = { [2] = { 0 } } },
            { headers = { "A", "B" }, rows = { { [1] = 0, [3] = 1 } } },
            { headers = { "A" }, rows = { "0" } },
            { headers = { "A", extra = "B" }, rows = {} },
        }) do
            local ok, value, err = pcall(model.normalize, tbl)
            assert.is_true(ok)
            assert.is_nil(value)
            assert.is_string(err)
        end
    end)

    it("rejects sparse or malformed materialized column arrays", function()
        local tbl = { headers = { "A" }, rows = { { 0 } } }
        for _, columns in ipairs({
            { false }, { {} }, { { heading = "B", values = { [2] = 1 } } },
            { [2] = { heading = "B", values = { 1 } } },
        }) do
            local ok, value, err = pcall(model.append_columns, tbl, columns)
            assert.is_true(ok)
            assert.is_nil(value)
            assert.is_string(err)
        end
    end)
end)
