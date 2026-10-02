local predicate = require("truth-table.predicate")

describe("standalone predicate pipeline", function()
    it("parses, discovers variables, binds, and evaluates without the core", function()
        local ast = assert(predicate.parse_expression("not (B and A) xor B"))
        assert.are.same({ "B", "A" }, predicate.variables(ast))
        local bound = assert(predicate.bind_columns(ast, { A = 1, B = 2 }))
        -- A is row position 1, B is position 2. These inputs distinguish both
        -- the binding order and a constant evaluator from the intended formula.
        for _, case in ipairs({
            { row = { 0, 0 }, expected = 1 }, { row = { 0, 1 }, expected = 0 },
            { row = { 1, 0 }, expected = 1 }, { row = { 1, 1 }, expected = 1 },
        }) do
            assert.are.equal(case.expected, predicate.eval_ast(bound, case.row))
        end
        assert.are.equal("¬(B ∧ A) ⊕ B", predicate.ast_to_heading(ast))
    end)

    it("copies nested nodes and preserves left-to-right post-order", function()
        local ast = assert(predicate.parse_expression("not A and (B or 0)"))
        local visited = {}
        local transformed = assert(predicate.transform_ast(ast, function(node)
            visited[#visited + 1] = node.name or node.type
            if node.type == "var" then node.name = node.name .. "_copy" end
            return node
        end))
        assert.are.same({ "A", "not", "B", "literal", "or", "paren", "and" }, visited)
        assert.are.equal("¬A_copy ∧ (B_copy ∨ 0)", predicate.ast_to_heading(transformed))
        assert.are.equal("¬A ∧ (B ∨ 0)", predicate.ast_to_heading(ast))
    end)

    it("short-circuits errors before visiting the right subtree", function()
        local ast = assert(predicate.parse_expression("A and B"))
        local visited = {}
        local value, err = predicate.transform_ast(ast, function(node)
            visited[#visited + 1] = node.name or node.type
            return nil, "stop"
        end)
        assert.is_nil(value)
        assert.are.equal("stop", err)
        assert.are.same({ "A" }, visited)
        assert.is_nil(predicate.transform_ast({ type = "unknown" }, function(node) return node end))
    end)
end)

describe("operator-driven rendering", function()
    local function variable(name) return { type = "var", name = name } end
    local function binary(kind, left, right) return { type = kind, left = left, right = right } end

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
                    local heading = predicate.ast_to_heading(ast)
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

    it("groups transformed operands underneath negation", function()
        local ast = assert(predicate.parse_expression("not A"))
        local transformed = assert(predicate.transform_ast(ast, function(node)
            if node.type == "var" then
                return binary("or", variable("B"), variable("C"))
            end
            return node
        end))
        assert.are.equal("¬(B ∨ C)", predicate.ast_to_heading(transformed))
        assert.are.equal("¬A", predicate.ast_to_heading(ast))
        local reparsed = assert(predicate.parse_expression(predicate.ast_to_heading(transformed)))
        assert.are.equal(0, predicate.eval_ast(reparsed, { B = 0, C = 1 }))
    end)

    it("retains left associativity and recognizes longest overlapping aliases", function()
        local ctx = { A = 0, B = 0, C = 0 }
        assert.are.equal(0, predicate.eval_ast(assert(predicate.parse_expression("A -> B -> C")), ctx))
        assert.are.equal(1, predicate.eval_ast(assert(predicate.parse_expression("A -> (B -> C)")), ctx))
        for _, alias in ipairs({ "=", "<=>", "<->", "=>", "->" }) do
            local ast = assert(predicate.parse_expression("A" .. alias .. "B"))
            assert.are.equal((alias == "=>" or alias == "->") and "implies" or "iff", ast.type)
            assert.are.equal(1, predicate.eval_ast(ast, ctx))
        end
    end)
end)

describe("predicate source diagnostics", function()
    it("retains byte spans without changing legacy token records", function()
        local tokens, err, locations = predicate.tokenize('  A ∧ `B, C`')
        assert.is_nil(err)
        assert.are.same({
            { type = 'ident', value = 'A' },
            { type = 'op', value = 'and' },
            { type = 'reference', value = 'B, C' },
        }, tokens)
        assert.are.same({
            { start_byte = 3, end_byte = 3 },
            { start_byte = 5, end_byte = 7 },
            { start_byte = 9, end_byte = 14 },
        }, locations.spans)
        assert.are.equal(15, locations.end_byte)
    end)

    it("points to unexpected tokens and end-of-input after multibyte symbols", function()
        for _, case in ipairs({
            { '  A ∧ )', 'Unexpected token: ) at byte 9' },
            { 'A ∧ ', 'Unexpected end of expression at byte 7' },
            { '(A or B', 'Expected ) at byte 8' },
            { 'A B', 'Unexpected token after expression: B at byte 3' },
            { '   ', 'Unexpected end of expression at byte 4' },
        }) do
            local ast, err = predicate.parse_expression(case[1])
            assert.is_nil(ast)
            assert.is_truthy(err:find(case[2], 1, true), err)
        end
    end)

    it("shows complete unexpected Unicode characters and reference positions", function()
        local _, unicode_err = predicate.parse_expression('A ∧ λ')
        assert.is_truthy(unicode_err:find('Unexpected character: λ at byte 7', 1, true))
        local _, reference_err = predicate.parse_expression('  `A')
        assert.is_truthy(reference_err:find('Unclosed column reference at byte 3', 1, true))
    end)

    it("falls back to token indices for manually supplied tokens", function()
        local tokens = assert(predicate.tokenize('A B'))
        local ast, err = predicate.parse_predicate(tokens)
        assert.is_nil(ast)
        assert.are.equal('Unexpected token after expression: B at token 2', err)
    end)
end)
