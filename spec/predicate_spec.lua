local predicate = require("truth-table.predicate")

describe("standalone predicate pipeline", function()
    it("parses, discovers variables, binds, and evaluates without the core", function()
        local ast = assert(predicate.parse_expression("not (B and A) or B"))
        assert.are.same({ "B", "A" }, predicate.variables(ast))
        local bound = assert(predicate.bind_columns(ast, { A = 1, B = 2 }))
        assert.are.equal(1, predicate.eval_ast(bound, { 1, 0 }))
        assert.are.equal("¬(B ∧ A) ∨ B", predicate.ast_to_heading(ast))
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
        for _, outer in ipairs(operators) do
            for _, inner in ipairs(operators) do
                for _, ast in ipairs({
                    binary(outer, binary(inner, variable("A"), variable("B")), variable("C")),
                    binary(outer, variable("A"), binary(inner, variable("B"), variable("C"))),
                }) do
                    local heading = predicate.ast_to_heading(ast)
                    local reparsed = assert(predicate.parse_expression(heading))
                    for a = 0, 1 do
                        for b = 0, 1 do
                            for c = 0, 1 do
                                local ctx = { A = a, B = b, C = c }
                                assert.are.equal(predicate.eval_ast(ast, ctx), predicate.eval_ast(reparsed, ctx), heading)
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
