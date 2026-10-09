-- Unit tests for truth-table.trees: the helpers that take a chain apart and
-- put one together, the copying transform, the canonical form and its text,
-- and the whole-expression De Morgan rewrite. The parser supplies the trees
-- and the evaluator is the oracle where one is needed.
local predicate = require("truth-table.predicate")
local result = require("truth-table.result")
local trees = require("truth-table.trees")

describe("tree helpers", function()
    local function parse(source) return assert(predicate.parse_expression(source)) end
    local function headings(nodes)
        local out = {}
        for i, node in ipairs(nodes) do out[i] = trees.heading(node) end
        return out
    end

    it("unparen strips every layer of parentheses and nothing else", function()
        assert.are.equal("var", trees.unparen(parse("((a))")).type)
        assert.are.equal("or", trees.unparen(parse("(a or (b))")).type)
        local bare = parse("a and b")
        assert.are.equal(bare, trees.unparen(bare))
    end)

    it("operands reads a run of one operator flat, through its parentheses", function()
        local ast = parse("a or (b or c) or d and e or (f or g) or (h and i)")
        assert.are.same({ "a", "b", "c", "d ∧ e", "f", "g", "h ∧ i" }, headings(trees.operands(ast, "or")))
        assert.are.same({ trees.heading(ast) }, headings(trees.operands(ast, "and")))
    end)

    it("fold builds a left-nested chain, splicing in operands that are chains of the operator", function()
        local chain = trees.fold("and", { parse("a"), parse("(b and c)"), parse("d or e") })
        assert.are.equal("a ∧ b ∧ c ∧ (d ∨ e)", trees.heading(chain))
        assert.are.equal("and", chain.left.type)
        assert.are.equal("or", trees.unparen(chain.right).type)
        local single = parse("a")
        assert.are.equal(single, trees.fold("or", { single }))
    end)
end)

describe("node constructors", function()
    local function parse(source) return assert(predicate.parse_expression(source)) end

    it("build the nodes the parser builds", function()
        local a, b = trees.var("a"), trees.var("b")
        assert.are.same(parse("a and not b"), trees.binary("and", a, trees.negation(b)))
        assert.are.same(parse("(a or :h2)"), trees.paren(trees.binary("or", a, trees.reference(2))))
        assert.are.same(parse("1"), trees.literal(1))
        assert.are.same(parse("⊤"), trees.literal(1, "⊤"))
    end)

    it("build the column nodes binding builds", function()
        local bound = assert(predicate.bind_columns(parse("a and :h2"), { a = 1 }, { "a", "b" }))
        assert.are.same(trees.binary("and", trees.column(1, nil, "a"), trees.column(2, "b")), bound)
    end)

    it("refuse a binary operator the operator table does not list", function()
        assert.has_error(function()
            trees.binary("nand", trees.var("a"), trees.var("b"))
        end, "Unknown binary operator: nand")
        assert.has_error(function()
            trees.binary("not", trees.var("a"), trees.var("b"))
        end, "Unknown binary operator: not")
    end)
end)

describe("trees.transform", function()
    it("copies nested nodes and preserves left-to-right post-order", function()
        local ast = assert(predicate.parse_expression("not A and (B or 0)"))
        local visited = {}
        local transformed = assert(trees.transform(ast, function(node)
            visited[#visited + 1] = node.name or node.type
            if node.type == "var" then node.name = node.name .. "_copy" end
            return node
        end))
        assert.are.same({ "A", "not", "B", "literal", "or", "paren", "and" }, visited)
        assert.are.equal("¬A_copy ∧ (B_copy ∨ 0)", trees.heading(transformed))
        assert.are.equal("¬A ∧ (B ∨ 0)", trees.heading(ast))
    end)

    it("short-circuits errors before visiting the right subtree", function()
        local ast = assert(predicate.parse_expression("A and B"))
        local visited = {}
        local value, err = trees.transform(ast, function(node)
            visited[#visited + 1] = node.name or node.type
            return nil, "stop"
        end)
        assert.is_nil(value)
        assert.are.equal("stop", err)
        assert.are.same({ "A" }, visited)
        assert.is_nil(trees.transform({ type = "unknown" }, function(node) return node end))
    end)
end)

describe("operator-driven rendering", function()
    local variable, binary = trees.var, trees.binary

    it("preserves semantics for every pair of nested binary operators", function()
        local operators = { "and", "or", "xor", "implies", "iff" }
        -- Independent truth tables, indexed by 00, 01, 10, 11. Neither parser
        -- nor evaluator supplies the oracle for rendering correctness.
        local truth = {
            ["and"] = { 0, 0, 0, 1 }, ["or"] = { 0, 1, 1, 1 },
            xor = { 0, 1, 1, 0 }, implies = { 1, 1, 0, 1 }, iff = { 1, 0, 0, 1 },
        }
        for _, outer in ipairs(operators) do
            for _, inner in ipairs(operators) do
                for side, ast in ipairs({
                    binary(outer, binary(inner, variable("A"), variable("B")), variable("C")),
                    binary(outer, variable("A"), binary(inner, variable("B"), variable("C"))),
                }) do
                    local heading = trees.heading(ast)
                    local reparsed = assert(predicate.parse_expression(heading))
                    for a = 0, 1 do
                        for b = 0, 1 do
                            for c = 0, 1 do
                                local ctx = { A = a, B = b, C = c }
                                local expected
                                if side == 1 then
                                    local inner_value = truth[inner][2 * a + b + 1]
                                    expected = truth[outer][2 * inner_value + c + 1]
                                else
                                    local inner_value = truth[inner][2 * b + c + 1]
                                    expected = truth[outer][2 * a + inner_value + 1]
                                end
                                assert.are.equal(expected, predicate.eval_ast(ast, ctx), heading)
                                assert.are.equal(expected, predicate.eval_ast(reparsed, ctx), heading)
                            end
                        end
                    end
                end
            end
        end
    end)

    it("renders one form per tree: an operand of a different operator is parenthesised", function()
        for source, heading in pairs({
            ["a and b or c"] = "(a ∧ b) ∨ c",
            ["(a and b) or c"] = "(a ∧ b) ∨ c",
            ["a or b and c"] = "a ∨ (b ∧ c)",
            ["S or A and not C or G and not C"] = "S ∨ (A ∧ ¬C) ∨ (G ∧ ¬C)",
            ["a and b implies c or d"] = "(a ∧ b) → (c ∨ d)",
            ["a xor b and c"] = "a ⊕ (b ∧ c)",
            ["a iff b or c"] = "a ⇔ (b ∨ c)",
            ["not (a or b) and c"] = "¬(a ∨ b) ∧ c",
        }) do
            assert.are.equal(heading, trees.heading(assert(predicate.parse_expression(source))), source)
        end
    end)

    it("writes a run of ∧ or of ∨ flat however it was grouped, and drops the parentheses nothing needs", function()
        for source, heading in pairs({
            ["a and b and c"] = "a ∧ b ∧ c",
            ["(a and b) and c"] = "a ∧ b ∧ c",
            ["a and (b and c)"] = "a ∧ b ∧ c",
            ["(a or b) or ((c or d) or e)"] = "a ∨ b ∨ c ∨ d ∨ e",
            ["a and (b and (c or (d or e)))"] = "a ∧ b ∧ (c ∨ d ∨ e)",
            ["((a)) and (not (b))"] = "a ∧ ¬b",
            ["(a or b)"] = "a ∨ b",
            ["not (a)"] = "¬a",
            ["not (not a)"] = "¬¬a",
            ["not ((a or b))"] = "¬(a ∨ b)",
        }) do
            assert.are.equal(heading, trees.heading(assert(predicate.parse_expression(source))), source)
        end
    end)

    it("keeps the grouping of →, ⊕ and ⇔ visible on either side", function()
        for source, heading in pairs({
            ["a implies b implies c"] = "(a → b) → c",
            ["a implies (b implies c)"] = "a → (b → c)",
            ["a iff b iff c"] = "(a ⇔ b) ⇔ c",
            ["a iff (b iff c)"] = "a ⇔ (b ⇔ c)",
            ["a xor b xor c"] = "(a ⊕ b) ⊕ c",
            ["a xor (b xor c)"] = "a ⊕ (b ⊕ c)",
        }) do
            assert.are.equal(heading, trees.heading(assert(predicate.parse_expression(source))), source)
        end
    end)

    it("gives every grouping of a ∧ or ∨ run the same tree", function()
        local flat = assert(trees.canonical(assert(predicate.parse_expression("a or b or c or d"))))
        for _, source in ipairs({ "a or (b or (c or d))", "(a or b) or (c or d)", "a or ((b or c) or d)" }) do
            assert.are.same(flat, assert(trees.canonical(assert(predicate.parse_expression(source)))), source)
        end
    end)

    it("is a tree transform: canonical puts paren nodes exactly where the text shows them", function()
        local tree = assert(trees.canonical(assert(predicate.parse_expression("((a)) and b or not (c)"))))
        assert.are.same({
            type = "or",
            left = { type = "paren", expr = {
                type = "and", left = { type = "var", name = "a" }, right = { type = "var", name = "b" },
            } },
            right = { type = "not", operand = { type = "var", name = "c" } },
        }, tree)
        local again = assert(trees.canonical(tree))
        assert.are.same(tree, again)
    end)

    it("renders its own output back to itself", function()
        for _, source in ipairs({
            "a and b or c", "not (not a or b) and (c implies d implies e)", "a or (b or c) or d and e xor f",
            "((a and (b))) iff not ((c)) or :h3 and 1", "a ∧ ⊤ ∨ ⊥",
        }) do
            local heading = trees.heading(assert(predicate.parse_expression(source)))
            assert.are.equal(heading, trees.heading(assert(predicate.parse_expression(heading))), source)
        end
    end)

    it("groups transformed operands underneath negation", function()
        local ast = assert(predicate.parse_expression("not A"))
        local transformed = assert(trees.transform(ast, function(node)
            if node.type == "var" then
                return binary("or", variable("B"), variable("C"))
            end
            return node
        end))
        assert.are.equal("¬(B ∨ C)", trees.heading(transformed))
        assert.are.equal("¬A", trees.heading(ast))
        local reparsed = assert(predicate.parse_expression(trees.heading(transformed)))
        assert.are.equal(0, predicate.eval_ast(reparsed, { B = 0, C = 1 }))
    end)
end)

describe("trees.heading", function()
    it("renders operators with their symbols", function()
        local function heading(expr)
            return trees.heading(assert(predicate.parse_expression(expr)))
        end
        assert.are.equal("A ∧ B", heading("A and B"))
        assert.are.equal("A ∨ B", heading("A or B"))
        assert.are.equal("A ⊕ B", heading("A xor B"))
        assert.are.equal("¬A", heading("!A"))
        assert.are.equal("A → B", heading("A -> B"))
        assert.are.equal("A ⇔ B", heading("A iff B"))
        assert.are.equal("(A ∨ B) ∧ C", heading("(A or B) and C"))
    end)
end)

describe("whole-expression De Morgan rewrites", function()
    -- Parse, rewrite and render in a row.
    local function de_morgan_expression(input)
        local ast, err = predicate.parse_expression(input)
        local rewritten, rewrite_err = result.bind(ast, err, trees.de_morgan)
        return result.bind(rewritten, rewrite_err, trees.heading)
    end

    it("rewrites both directions and agrees with independent Boolean outcomes", function()
        for _, case in ipairs({
            { source = 'not (A and B)', heading = '¬A ∨ ¬B', values = { 1, 1, 1, 0 } },
            { source = 'not (A or B)', heading = '¬A ∧ ¬B', values = { 1, 0, 0, 0 } },
            { source = 'not A or not B', heading = '¬(A ∧ B)', values = { 1, 1, 1, 0 } },
            { source = '(not A) and (not B)', heading = '¬(A ∨ B)', values = { 1, 0, 0, 0 } },
        }) do
            local ast = assert(predicate.parse_expression(case.source))
            local before = trees.heading(ast)
            local rewritten = assert(trees.de_morgan(ast))
            assert.are.equal(case.heading, trees.heading(rewritten))
            for a = 0, 1 do
                for b = 0, 1 do
                    local expected = case.values[2 * a + b + 1]
                    assert.are.equal(expected, predicate.eval_ast(ast, { A = a, B = b }))
                    assert.are.equal(expected, predicate.eval_ast(rewritten, { A = a, B = b }))
                end
            end
            rewritten.type = 'literal'
            assert.are.equal(before, trees.heading(ast))
        end
    end)

    it("reads a chain as one run: every operand negated, the operator flipped", function()
        assert.are.equal('¬A ∨ ¬B ∨ ¬C', de_morgan_expression('not (A and B and C)'))
        assert.are.equal('¬A ∨ ¬B ∨ ¬C', de_morgan_expression('not (A and (B and C))'))
        assert.are.equal('¬(A ∧ B ∧ C)', de_morgan_expression('not A or not B or not C'))
        assert.are.equal('¬(A ∧ B ∧ C)', de_morgan_expression('(not A or not B) or not C'))
        assert.are.equal('¬(A ∨ B ∨ (C ∧ D))', de_morgan_expression('not A and not B and not (C and D)'))
        local ast, err = de_morgan_expression('not A or not B or C')
        assert.is_nil(ast)
        assert.are.equal('No De Morgan rewrite applies to the whole expression', err)
    end)

    it("treats root parentheses transparently and preserves necessary nested grouping", function()
        assert.are.equal('¬A ∨ ¬B', de_morgan_expression('(not (A and B))'))
        assert.are.equal('¬(A ∨ B) ∨ ¬C', de_morgan_expression('not ((A or B) and C)'))
        assert.are.equal('¬:h2 ∧ ¬B', de_morgan_expression('not (:h2 or B)'))
        local ast, err = de_morgan_expression('A or not (B and C)')
        assert.is_nil(ast)
        assert.are.equal('No De Morgan rewrite applies to the whole expression', err)
        assert.is_nil(de_morgan_expression('A and'))
    end)
end)

describe("trees.rendered", function()
    local function parse(source) return assert(predicate.parse_expression(source)) end
    local function lit(tree, selected)
        local text, regions = trees.rendered(tree, selected)
        local region = regions[1]
        return region and text:sub(region[1] + 1, region[2]), text
    end

    it("renders an unannotated tree without a range", function()
        local text, regions = trees.rendered(parse("a ∨ (b ∧ c)"))
        assert.are.equal("a ∨ (b ∧ c)", text)
        assert.are.same({}, regions)
    end)

    it("transports external provenance through flattening", function()
        local tree = parse("a ∨ (b ∨ c)")
        assert.are.equal("b ∨ c", (lit(tree, { tree.right })))
        assert.is_nil(tree.right.changed)
        assert.is_nil(tree.right.expr.changed)
    end)

    it("takes a produced subtree whole, including necessary grouping", function()
        local tree = parse("a ∨ (b ∧ c)")
        assert.are.equal("(b ∧ c)", (lit(tree, { tree.right })))
        tree = parse("a ∨ ¬(b ∧ c)")
        assert.are.equal("¬(b ∧ c)", (lit(tree, { tree.right })))
    end)

    it("counts multibyte symbols and preserves selected leaf identities", function()
        local tree = parse("¬a ∧ ¬(b ∨ c)")
        local inner = tree.right.operand.expr
        assert.are.equal("b ∨ c", (lit(tree, { inner.left, inner.right })))
        assert.are.equal("a", (lit(tree, { tree.left.operand })))
    end)

    it("maps provenance to independent canonical output nodes", function()
        local tree = parse("a ∨ (b ∨ c)")
        local canonical, selected = trees.canonical(tree, { tree.right })
        assert.are.equal("b ∨ c", (lit(canonical, selected)))
        assert.are.equal("a ∨ b ∨ c", trees.heading(tree))
        assert.are_not.equal(tree.right.expr.left, selected[1])
        assert.are.same(canonical, assert(trees.canonical(canonical)))
    end)

    it("keeps disjoint produced regions separate", function()
        local tree = parse("a ∨ b ∨ c")
        local text, regions = trees.rendered(tree, { tree.left.left, tree.right })
        assert.are.same({ { 0, 1 }, { #"a ∨ b ∨ ", #text } }, regions)
    end)
end)
