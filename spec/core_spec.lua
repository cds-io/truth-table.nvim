-- Unit tests for truth-table.core, the table pipeline over the semantic
-- model, and for truth-table.table_model itself. These run under a bare Lua
-- interpreter via busted (`busted` from the project root): neither module has
-- a Neovim dependency. The vim-coupled layer (init.lua: buffer scanning,
-- commands, keymaps) has the *_nvim_spec.lua files.

local core = require("truth-table.core")
local model = require("truth-table.table_model")
local predicate = require("truth-table.predicate")

local two_variables = { { 0, 0 }, { 0, 1 }, { 1, 0 }, { 1, 1 } }

describe("table_model.generate_rows", function()
    it("produces 2^n rows, MSB-first", function()
        assert.are.same({ { 0 }, { 1 } }, model.generate_rows(1))
        assert.are.same(two_variables, model.generate_rows(2))
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

describe("core.parse", function()
    it("separates headers from data rows (skipping the separator)", function()
        local tbl = assert(core.parse({
            "| A | B |",
            "|:-:|:-:|",
            "| 0 | 1 |",
            "| 1 | 0 |",
        }))
        assert.are.same({ headers = { "A", "B" }, rows = { { 0, 1 }, { 1, 0 } }, encoding = "bits" }, tbl)
    end)
end)

describe("core.expand", function()
    local tbl = { headers = { "A", "B" }, rows = two_variables, encoding = "bits" }

    it("appends a computed column per predicate", function()
        local expanded = assert(core.expand(tbl, { "A and B" }))
        assert.are.same({ "A", "B", "A ∧ B" }, expanded.headers)
        assert.are.same({
            { 0, 0, 0 },
            { 0, 1, 0 },
            { 1, 0, 0 },
            { 1, 1, 1 },
        }, expanded.rows)
    end)

    it("supports multiple predicates", function()
        local expanded = assert(core.expand(tbl, { "A or B", "A xor B" }))
        assert.are.same({ "A", "B", "A ∨ B", "A ⊕ B" }, expanded.headers)
    end)

    it("returns nil + message for an unknown column", function()
        local expanded, err = core.expand(tbl, { "A and Z" })
        assert.is_nil(expanded)
        assert.is_truthy(err:match("Unknown column: Z"))
    end)

    it("returns nil + message for a parse error", function()
        local expanded, err = core.expand(tbl, { "A &" })
        assert.is_nil(expanded)
        assert.is_truthy(err:match("Parse error"))
    end)

    it("does not mutate the input table", function()
        assert(core.expand(tbl, { "A and B" }))
        assert.are.same({ "A", "B" }, tbl.headers)
        assert.are.same({ { 0, 0 }, { 0, 1 }, { 1, 0 }, { 1, 1 } }, tbl.rows)
    end)
end)

describe("core.build", function()
    it("keeps the integer and name-list forms", function()
        local tbl = assert(core.build("2"))
        assert.are.same({ headers = { "A", "B" }, rows = two_variables, encoding = "bits" }, tbl)

        tbl = assert(core.build("p q r"))
        assert.are.same({ "p", "q", "r" }, tbl.headers)
        assert.are.equal(8, #tbl.rows)
    end)

    it("derives the variables from |-separated expressions, in order of first appearance", function()
        local tbl = assert(core.build("(m ∧  (a ⊕ b) ∨ (¬m ∧ (a ∧ b))) | m ⊕ (a ∧ b)"))
        assert.are.same({ "m", "a", "b", "(m ∧ (a ⊕ b)) ∨ (¬m ∧ a ∧ b)", "m ⊕ (a ∧ b)" }, tbl.headers)
        assert.are.same({
            { 0, 0, 0, 0, 0 },
            { 0, 0, 1, 0, 0 },
            { 0, 1, 0, 0, 0 },
            { 0, 1, 1, 1, 1 },
            { 1, 0, 0, 0, 1 },
            { 1, 0, 1, 1, 1 },
            { 1, 1, 0, 1, 1 },
            { 1, 1, 1, 0, 0 },
        }, tbl.rows)
    end)

    it("accepts commas and the keyword operators too", function()
        local tbl = assert(core.build("p and q, p xor r"))
        assert.are.same({ "p", "q", "r", "p ∧ q", "p ⊕ r" }, tbl.headers)
    end)

    it("lets a bare variable fix the column order without adding a column", function()
        local tbl = assert(core.build("b | a | a -> b"))
        assert.are.same({ "b", "a", "a → b" }, tbl.headers)
    end)

    it("emits a repeated expression once", function()
        local tbl = assert(core.build("a and b | a ∧ b"))
        assert.are.same({ "a", "b", "a ∧ b" }, tbl.headers)
    end)

    it("returns nil + message for a parse error", function()
        local tbl, err = core.build("a and | b")
        assert.is_nil(tbl)
        assert.is_truthy(err:match("Parse error"))
    end)

    it("returns nil + message when no expression names a variable", function()
        local tbl, err = core.build("1 or 0")
        assert.is_nil(tbl)
        assert.is_truthy(err:match("No variables"))
    end)

    it("shows the two selector forms agree once the inner operator is iff", function()
        local tbl = assert(core.build("(m ∧ (a ⊕ b) ∨ (¬m ∧ (a=b))) | m ⊕ (a=b)"))
        assert.are.same({ "m", "a", "b", "(m ∧ (a ⊕ b)) ∨ (¬m ∧ (a ⇔ b))", "m ⊕ (a ⇔ b)" }, tbl.headers)
        assert.are.same({
            { 0, 0, 0, 1, 1 },
            { 0, 0, 1, 0, 0 },
            { 0, 1, 0, 0, 0 },
            { 0, 1, 1, 1, 1 },
            { 1, 0, 0, 0, 0 },
            { 1, 0, 1, 1, 1 },
            { 1, 1, 0, 1, 1 },
            { 1, 1, 1, 0, 0 },
        }, tbl.rows)
    end)

    it("returns nil + message past 10 variables", function()
        local tbl, err = core.build("a and b and c and d and e and f and g and h and i and j and k")
        assert.is_nil(tbl)
        assert.is_truthy(err:match("Too many variables"))
    end)

    it("checks each construction form against a fixed outcome", function()
        for _, case in ipairs({
            { input = "2", headers = { "A", "B" }, rows = two_variables },
            { input = "p q", headers = { "p", "q" }, rows = two_variables },
            {
                input = "B | A | A implies B",
                headers = { "B", "A", "A → B" },
                rows = { { 0, 0, 1 }, { 0, 1, 0 }, { 1, 0, 1 }, { 1, 1, 1 } },
            },
        }) do
            assert.are.same({ headers = case.headers, rows = case.rows, encoding = "bits" }, core.build(case.input))
        end
        assert.is_nil(core.build(""))
        local tbl = assert(core.build("A"))
        local expanded, err = core.expand(tbl, { "missing" })
        assert.is_nil(expanded)
        assert.are.equal("Unknown column: missing", err)
    end)
end)

describe("core.args_from_lines", function()
    it("joins lines with the column delimiter, skipping blank ones", function()
        assert.are.equal(
            "m | a  | b | m xor a | a and b",
            core.args_from_lines({ "m | a  | b", "  m xor a ", "", "a and b" })
        )
    end)

    it("feeds build: a first line of bare variables pins the order", function()
        local args =
            core.args_from_lines({ "m | a  | b", "(m ∧  (a ⊕ b) ∨ (¬m ∧ (a ∧ b))) ", "m ⊕ (a ∧ b)" })
        local tbl = assert(core.build(args))
        assert.are.same({ "m", "a", "b", "(m ∧ (a ⊕ b)) ∨ (¬m ∧ a ∧ b)", "m ⊕ (a ∧ b)" }, tbl.headers)
        assert.are.equal(8, #tbl.rows)
    end)

    it("leaves a single line as it is, so the classic forms still work", function()
        assert.are.same({ "p", "q" }, assert(core.build(core.args_from_lines({ "p q" }))).headers)
    end)
end)

describe("core.format", function()
    it("renders a centered, aligned markdown table", function()
        local lines = assert(core.format({ headers = { "A", "B" }, rows = { { 0, 1 } }, encoding = "bits" }))
        assert.are.same({
            "|  A  |  B  |",
            "|:---:|:---:|",
            "|  0  |  1  |",
        }, lines)
    end)

    it("widens columns to fit the widest cell", function()
        local lines = assert(core.format({ headers = { "A", "long" }, rows = { { 0, 1 } }, encoding = "bits" }))
        -- "long" is width 4, so column 2's interior is 4 wide.
        assert.are.equal("|  A  | long |", lines[1])
        assert.are.equal("|:---:|:----:|", lines[2])
        assert.are.equal("|  0  |  1   |", lines[3])
    end)

    it("spells the cells in the table's encoding", function()
        local lines = assert(core.format({ headers = { "A", "B" }, rows = { { 0, 1 } }, encoding = "tf" }))
        assert.are.equal("|  F  |  T  |", lines[3])
    end)
end)

describe("table pipeline", function()
    it("expands a toggled table in its F/T encoding", function()
        local tbl = assert(core.build("A B"))
        local toggled = assert(core.toggle(tbl))
        local expanded = assert(core.expand(toggled, { "not A", "A iff B" }))
        assert.are.equal("tf", expanded.encoding)
        assert.are.same({
            { "F", "F", "T", "T" },
            { "F", "T", "T", "F" },
            { "T", "F", "F", "F" },
            { "T", "T", "F", "T" },
        }, model.render_rows(expanded))
        assert.are.equal("bits", tbl.encoding)
        assert.are.same(tbl, core.toggle(toggled))
    end)

    it("refuses ragged rows, duplicate headings, invalid cells and mixed encodings where cells are read", function()
        for _, case in ipairs({
            { headers = { "A", "B" }, rows = { { "1" } } },
            { headers = { "A" }, rows = { { "1", "0" } } },
            { headers = { "A", "A" }, rows = { { "0", "1" } } },
            { headers = { "A" }, rows = { { "x" } } },
            { headers = { "A" }, rows = { { 1 } } },
            { headers = { "A", "B" }, rows = { { "F", "1" } } },
            { headers = { " A" }, rows = {} },
            { headers = {}, rows = {} },
        }) do
            local value, err = model.parse(case.headers, case.rows)
            assert.is_nil(value)
            assert.is_string(err)
        end
        assert.are.same({ headers = { "A" }, rows = {}, encoding = "bits" }, model.parse({ "A" }, {}))
    end)

    it("validates the Markdown boundary before editing", function()
        assert.is_nil(core.parse({ "|A|", "not a separator", "|0|" }))
        assert.is_nil(core.parse({ "|A|", "|---|---|", "|0|" }))
        assert.is_nil(core.parse({ "|A|", "|---|", "|0|1|" }))
        assert.is_nil(core.parse({ "|A|", "|---|", "|x|" }))
        assert.is_nil(core.parse({ "|A|A|", "|---|---|", "|0|1|" }))
        assert.is_nil(core.parse({ "|A|B|", "|---|---|", "|F|1|" }))
    end)

    it("does not duplicate computed columns on repeated expansion", function()
        local tbl = assert(core.build("A and B"))
        assert.are.same(tbl, core.expand(tbl, { "A ∧ B", "A and B" }))
    end)

    it("parses each construction expression once", function()
        local original, calls = predicate.parse_expression, 0
        predicate.parse_expression = function(input)
            calls = calls + 1
            return original(input)
        end
        finally(function()
            predicate.parse_expression = original
        end)
        local tbl = assert(core.build("A and B | not A"))
        assert.are.same({ "A", "B", "A ∧ B", "¬A" }, tbl.headers)
        assert.are.same({
            { 0, 0, 0, 1 },
            { 0, 1, 0, 1 },
            { 1, 0, 0, 0 },
            { 1, 1, 1, 0 },
        }, tbl.rows)
        assert.are.equal(2, calls)
    end)
end)

describe("stored column references", function()
    it("uses stored values after source columns have been dropped", function()
        local tbl = { headers = { "B", "A ∧ B" }, rows = { { 0, 0 }, { 1, 1 } }, encoding = "bits" }
        local expanded = assert(core.expand(tbl, { "not :h2" }))
        assert.are.same({ "B", "A ∧ B", "¬“A ∧ B”" }, expanded.headers)
        assert.are.same({ { 0, 0, 1 }, { 1, 1, 0 } }, expanded.rows)
        assert.is_nil(core.expand(tbl, { "not (A and B)" }))
    end)

    it("distinguishes a stored value from recomputing its displayed formula", function()
        local tbl = { headers = { "A", "B", "A ∧ B" }, rows = { { 1, 1, 0 } }, encoding = "bits" }
        local expanded = assert(core.expand(tbl, { "not :h3", "not (A and B)" }))
        assert.are.same({ { 1, 1, 0, 1, 0 } }, expanded.rows)
    end)

    it("renders a literal reference heading over a comma-bearing label", function()
        local expanded = assert(core.expand({ headers = { "p, q" }, rows = { { 1 } }, encoding = "tf" }, { "not :h1" }))
        assert.are.same({ headers = { "p, q", "¬“p, q”" }, rows = { { 1, 0 } }, encoding = "tf" }, expanded)
    end)

    it("resolves every index against the input table before appending columns", function()
        local tbl = { headers = { "p, q", "[arbitrary] `label`" }, rows = { { 0, 1 } }, encoding = "bits" }
        local expanded = assert(core.expand(tbl, { "not :h2", ":h1 xor :h2" }))
        assert.are.same({ { 0, 1, 0, 1 } }, expanded.rows)
        assert.are.equal("¬“[arbitrary] `label`”", expanded.headers[3])
        local invalid, err = core.expand(tbl, { "not :h1", ":h3" })
        assert.is_nil(invalid)
        assert.are.equal("Column reference out of range: :h3", err)
        assert.are.same({ { 0, 1 } }, tbl.rows)
        assert.are.equal(2, #tbl.headers)
    end)

    it("rejects a reference past the table, and any reference during table creation", function()
        assert.is_nil(core.expand({ headers = { "A" }, rows = { { 0 } }, encoding = "bits" }, { ":h2" }))
        local tbl, err = core.build("A and :h1")
        assert.is_nil(tbl)
        assert.are.equal("Column references require an existing table", err)
    end)
end)

describe("pure model edits", function()
    it("composes edits on a parsed table while retaining F/T encoding", function()
        local parsed = assert(model.parse({ "A", "B" }, { { "F", "T" }, { "T", "F" } }))
        assert.are.same({ headers = { "A", "B" }, rows = { { 0, 1 }, { 1, 0 } }, encoding = "tf" }, parsed)
        local dropped = assert(model.drop_column(parsed, 1))
        assert.are.same({ { "T" }, { "F" } }, model.render_rows(dropped))
        local remaining = assert(model.drop_row(dropped, 1))
        assert.are.same({ { "F" } }, model.render_rows(remaining))
        local toggled = model.toggle(remaining)
        assert.are.same({ { "0" } }, model.render_rows(toggled))
        assert.are.same(remaining, model.toggle(toggled))
        assert.are.same({ { 0, 1 }, { 1, 0 } }, parsed.rows)
    end)

    it("leaves the input table as it was", function()
        local original = { headers = { "A", "B" }, rows = { { 0, 1 }, { 1, 0 } }, encoding = "tf" }
        assert(model.drop_row(original, 1))
        assert(model.drop_column(original, 1))
        model.toggle(original)
        assert(model.append_columns(original, { { heading = "C", values = { 1, 1 } } }))
        assert.are.same({ headers = { "A", "B" }, rows = { { 0, 1 }, { 1, 0 } }, encoding = "tf" }, original)
    end)

    it("preserves the mode when the last data row is dropped", function()
        local empty = assert(model.drop_row({ headers = { "A" }, rows = { { 1 } }, encoding = "tf" }, 1))
        assert.are.equal("tf", empty.encoding)
        assert.are.same({}, empty.rows)
        assert.are.equal("bits", model.toggle(empty).encoding)
    end)

    it("rejects invalid indices and dropping the only column", function()
        local tbl = { headers = { "A", "B" }, rows = { { 0, 1 } }, encoding = "bits" }
        for _, index in ipairs({ 0, -1, 3, 1.5, "1" }) do
            assert.is_nil(model.drop_row(tbl, index))
            assert.is_nil(model.drop_column(tbl, index))
            assert.is_nil(model.equivalent_columns(tbl, index))
        end
        assert.is_nil(model.drop_column({ headers = { "A" }, rows = {}, encoding = "bits" }, 1))
    end)

    it("reads a column's equivalence class off the rows, the column among them", function()
        -- A, A → B and ¬A ∨ B over two variables: the two spellings of the
        -- implication agree on every row, A matches neither.
        local tbl = {
            headers = { "A", "B", "A → B", "¬A ∨ B" },
            rows = { { 0, 0, 1, 1 }, { 0, 1, 1, 1 }, { 1, 0, 0, 0 }, { 1, 1, 1, 1 } },
            encoding = "bits",
        }
        assert.are.same({ 3, 4 }, model.equivalent_columns(tbl, 3))
        assert.are.same({ 3, 4 }, model.equivalent_columns(tbl, 4))
        assert.are.same({ 1 }, model.equivalent_columns(tbl, 1))
        assert.are.same({ 2 }, model.equivalent_columns(tbl, 2))
    end)

    it("makes every column equivalent, vacuously, when there are no data rows", function()
        local empty = { headers = { "A", "B" }, rows = {}, encoding = "bits" }
        assert.are.same({ 1, 2 }, model.equivalent_columns(empty, 1))
    end)
end)

describe("semantic core pipeline", function()
    it("composes all edits using numeric cells until the Markdown boundary", function()
        local tbl = assert(core.build("A and B"))
        assert.are.same({ 1, 1, 1 }, tbl.rows[4])
        local toggled = assert(core.toggle(tbl))
        local dropped = assert(core.drop_column(toggled, 1))
        local expanded = assert(core.expand(dropped, { "not :h2" }))
        assert.are.equal("tf", expanded.encoding)
        assert.are.same({ 1, 1, 0 }, expanded.rows[4])
        local edited = assert(core.drop_row(expanded, 1))
        assert.are.same({
            headers = { "B", "A ∧ B", "¬“A ∧ B”" },
            rows = { { 1, 0, 1 }, { 0, 0, 1 }, { 1, 1, 0 } },
            encoding = "tf",
        }, edited)
        assert.are.same(edited, core.parse(assert(core.format(edited))))
        assert.are.equal("bits", tbl.encoding)
        assert.are.same({ 1, 1, 1 }, tbl.rows[4])
    end)
end)

describe("materialized column model", function()
    it("appends columns purely and deduplicates headings in one place", function()
        local tbl = { headers = { "A" }, rows = { { 0 }, { 1 } }, encoding = "tf" }
        local columns = {
            { heading = "¬A", values = { 1, 0 } },
            { heading = "¬A", values = { 1, 0 } },
            { heading = "A", values = { 0, 1 } },
        }
        local extended = model.append_columns(tbl, columns)
        assert.are.same({ headers = { "A", "¬A" }, rows = { { 0, 1 }, { 1, 0 } }, encoding = "tf" }, extended)
        extended.rows[1][1] = 1
        extended.headers[1] = "changed"
        assert.are.same({ { 0 }, { 1 } }, tbl.rows)
        assert.are.same({ "A" }, tbl.headers)
        assert.are.same({ 1, 0 }, columns[1].values)
    end)
end)

describe("references to reference-generated headings", function()
    it("chains stored-column operations after source columns are dropped", function()
        local tbl = { headers = { "A" }, rows = { { 0 }, { 1 } }, encoding = "bits" }
        local first = assert(core.expand(tbl, { "not :h1" }))
        local dropped = assert(core.drop_column(first, 1))
        local second = assert(core.expand(dropped, { "not :h1" }))
        assert.are.same({
            headers = { "¬“A”", "¬“¬“A””" },
            rows = { { 1, 0 }, { 0, 1 } },
            encoding = "bits",
        }, second)
        local reparsed = assert(core.parse(assert(core.format(second))))
        local third = assert(core.expand(reparsed, { "not :h2" }))
        assert.are.same({ { 1, 0, 1 }, { 0, 1, 0 } }, third.rows)
    end)
end)
