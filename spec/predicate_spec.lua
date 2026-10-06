local predicate = require("truth-table.predicate")
local trees = require("truth-table.trees")

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
        assert.are.equal("¬(B ∧ A) ⊕ B", trees.heading(ast))
    end)
end)

describe("operator aliases", function()
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
        local tokens, err, locations = predicate.tokenize('  A ∧ :h2')
        assert.is_nil(err)
        assert.are.same({
            { type = 'ident', value = 'A' },
            { type = 'op', value = 'and' },
            { type = 'reference', value = 2 },
        }, tokens)
        assert.are.same({
            { start_byte = 3, end_byte = 3 },
            { start_byte = 5, end_byte = 7 },
            { start_byte = 9, end_byte = 11 },
        }, locations.spans)
        assert.are.equal(12, locations.end_byte)
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
        local _, reference_err = predicate.parse_expression('  :h')
        assert.is_truthy(reference_err:find('Invalid column reference at byte 3', 1, true))
    end)

    it("falls back to token indices for manually supplied tokens", function()
        local tokens = assert(predicate.tokenize('A B'))
        local ast, err = predicate.parse_predicate(tokens)
        assert.is_nil(ast)
        assert.are.equal('Unexpected token after expression: B at token 2', err)
    end)
end)

describe("truth constants", function()
    it("reads ⊤ and ⊥ as 1 and 0", function()
        local top = assert(predicate.parse_expression("A and ⊤"))
        local bottom = assert(predicate.parse_expression("A or ⊥"))
        for a = 0, 1 do
            assert.are.equal(a, predicate.eval_ast(top, { A = a }))
            assert.are.equal(a, predicate.eval_ast(bottom, { A = a }))
        end
        assert.are.same({ "A" }, assert(predicate.variables(top)))
    end)

    it("renders each constant as it was typed, through a copy as well", function()
        for source, heading in pairs({ ["A or ⊤"] = "A ∨ ⊤", ["⊥ and A"] = "⊥ ∧ A", ["A or 1"] = "A ∨ 1" }) do
            local ast = assert(predicate.parse_expression(source))
            assert.are.equal(heading, trees.heading(ast))
            local copy = assert(trees.transform(ast, function(node)
                return node
            end))
            assert.are.equal(heading, trees.heading(copy))
        end
    end)

    it("leaves a digit's token and node as they were", function()
        local tokens = assert(predicate.tokenize("1 or ⊤"))
        assert.are.same({ type = "literal", value = "1" }, tokens[1])
        assert.are.same({ type = "literal", value = "⊤" }, tokens[3])
        assert.are.same({ type = "literal", value = 1 }, assert(predicate.parse_expression("1")))
    end)

    it("spans the symbol's three bytes", function()
        local source = "A ∧ ⊤ ∧ B"
        local ast = assert(predicate.parse_located(source))
        assert.are.equal("⊤", source:sub(ast.left.right.span.start_byte, ast.left.right.span.end_byte))
    end)

    it("reads the words true and false as ⊤ and ⊥", function()
        local ast = assert(predicate.parse_expression("A and true or false"))
        assert.are.equal("(A ∧ ⊤) ∨ ⊥", trees.heading(ast))
        assert.are.same({ "A" }, assert(predicate.variables(ast)))
        for a = 0, 1 do
            assert.are.equal(a, predicate.eval_ast(ast, { A = a }))
        end
        assert.are.equal("truest", trees.heading(assert(predicate.parse_expression("truest"))))
    end)

    it("reserves the words, so a list of names holding one is an expression", function()
        assert.is_true(predicate.is_expression_input("p true"))
        assert.is_true(predicate.is_expression_input("false"))
        assert.is_false(predicate.is_expression_input("p truthy"))
    end)

    it("spans a word constant from its first letter to its last", function()
        local source = "A or false"
        local ast = assert(predicate.parse_located(source))
        assert.are.equal("false", source:sub(ast.right.span.start_byte, ast.right.span.end_byte))
    end)
end)

describe("positional column references", function()
    it("parses indices and retains expression syntax", function()
        local ast = assert(predicate.parse_expression('not :h12'))
        assert.are.same({ type = 'not', operand = { type = 'reference', index = 12 } }, ast)
        assert.are.equal('¬:h12', trees.heading(ast))
        assert.are.same({ 'not :h12', 'A' }, predicate.split_expressions('not :h12, A', ','))
    end)

    it("rejects invalid indices and named reference syntax", function()
        for _, input in ipairs({ ':h0', ':h', ':h-1', ':h1x', ':h1.5', ':H1', '[A]', '`A`' }) do
            local ast, err = predicate.parse_expression(input)
            assert.is_nil(ast)
            assert.is_string(err)
        end
    end)
end)

describe("located parsing", function()
    local function span_text(source, node)
        return source:sub(node.span.start_byte, node.span.end_byte)
    end

    it("records the bytes each node was read from", function()
        local source = "S ∨ (A ∧ ¬C)"
        local ast = assert(predicate.parse_located(source))
        assert.are.equal(source, span_text(source, ast))
        assert.are.equal("S", span_text(source, ast.left))
        assert.are.equal("(A ∧ ¬C)", span_text(source, ast.right))
        assert.are.equal("A ∧ ¬C", span_text(source, ast.right.expr))
        assert.are.equal("¬C", span_text(source, ast.right.expr.right))
        assert.are.equal("C", span_text(source, ast.right.expr.right.operand))
    end)

    it("spans a left-nested chain from its first operand", function()
        local source = "A or B or :h3"
        local ast = assert(predicate.parse_located(source))
        assert.are.equal("A or B", span_text(source, ast.left))
        assert.are.equal(":h3", span_text(source, ast.right))
    end)

    it("evaluates, renders, and copies like an unlocated tree", function()
        local located = assert(predicate.parse_located("not (A and 1)"))
        local plain = assert(predicate.parse_expression("not (A and 1)"))
        assert.is_nil(plain.span)
        assert.are.equal(trees.heading(plain), trees.heading(located))
        assert.are.equal(predicate.eval_ast(plain, { A = 1 }), predicate.eval_ast(located, { A = 1 }))
        local copy = assert(trees.transform(located, function(node)
            return node
        end))
        assert.are.same(plain, copy)
    end)

    it("reports parse errors exactly as parse_expression does", function()
        local _, plain_err = predicate.parse_expression("A and")
        local ast, err = predicate.parse_located("A and")
        assert.is_nil(ast)
        assert.are.equal(plain_err, err)
    end)
end)

describe("predicate.tokenize", function()
    it("recognizes idents, operators, parens, and literals", function()
        local toks = assert(predicate.tokenize("A and !B"))
        assert.are.same({ type = "ident", value = "A" }, toks[1])
        assert.are.same({ type = "op", value = "and" }, toks[2])
        assert.are.same({ type = "op", value = "!" }, toks[3])
        assert.are.same({ type = "ident", value = "B" }, toks[4])
    end)

    it("maps -> to implies", function()
        local toks = assert(predicate.tokenize("A -> B"))
        assert.are.same({ type = "op", value = "implies" }, toks[2])
    end)

    it("errors on an unexpected character", function()
        local toks, err = predicate.tokenize("A & B")
        assert.is_nil(toks)
        assert.is_truthy(err:match("Unexpected character"))
    end)

    it("accepts the logic symbols the headings are rendered with", function()
        local toks = assert(predicate.tokenize("¬A ∧ B ∨ C ⊕ D → E"))
        local ops = {}
        for _, tok in ipairs(toks) do
            if tok.type == "op" then
                ops[#ops + 1] = tok.value
            end
        end
        assert.are.same({ "not", "and", "or", "xor", "implies" }, ops)
    end)

    it("maps ⇒ to implies", function()
        local toks = assert(predicate.tokenize("A ⇒ B"))
        assert.are.same({ type = "op", value = "implies" }, toks[2])
    end)
end)

describe("predicate parsing + evaluation", function()
    -- Parse + evaluate against a context of variable names, the way expansion does.
    local function eval(expr, ctx)
        local tokens = assert(predicate.tokenize(expr))
        local ast = assert(predicate.parse_predicate(tokens))
        return predicate.eval_ast(ast, ctx)
    end

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
        local toks = assert(predicate.tokenize("A B"))
        local ast, err = predicate.parse_predicate(toks)
        assert.is_nil(ast)
        assert.is_truthy(err:match("Unexpected token after expression"))
    end)
end)

describe("predicate.bind_columns", function()
    local columns = { A = 1, B = 2 }

    it("binds every variable to its column's position", function()
        local ast = assert(predicate.parse_expression("A and B"))
        assert.are.same({
            type = "and",
            left = { type = "column", index = 1, variable = "A" },
            right = { type = "column", index = 2, variable = "B" },
        }, predicate.bind_columns(ast, columns))
    end)

    it("flags an unknown column", function()
        local ast = assert(predicate.parse_expression("A and Z"))
        local bound, err = predicate.bind_columns(ast, columns)
        assert.is_nil(bound)
        assert.is_truthy(err:match("Unknown column: Z"))
    end)

    it("binds a reference to its position without mutating the parsed tree", function()
        local ast = assert(predicate.parse_expression("not :h2"))
        local bound = assert(predicate.bind_columns(ast, { ["A ∧ B"] = 2 }, { "B", "A ∧ B" }))
        assert.are.equal(1, predicate.eval_ast(bound, { 1, 0 }))
        assert.are.equal("reference", ast.operand.type)
        assert.are.equal("column", bound.operand.type)
        assert.are.equal("¬“A ∧ B”", trees.heading(bound))
    end)

    it("renders a bound reference as its quoted label, commas included", function()
        local ast = assert(predicate.parse_expression("not :h1"))
        assert.are.equal("¬“p, q”", trees.heading(assert(predicate.bind_columns(ast, {}, { "p, q" }))))
    end)
end)

describe("predicate.split_expressions", function()
    it("splits on any of the delimiters given", function()
        assert.are.same({ "not :h1", "A" }, predicate.split_expressions("not :h1, A", ","))
    end)

    it("rejects an empty expression between or around delimiters", function()
        for _, input in ipairs({ "A,,B", "A|", "|A", "A,," }) do
            assert.is_nil(predicate.split_expressions(input, "|,"))
        end
    end)
end)

describe("predicate.is_expression_input", function()
    it("treats an integer or a plain name list as the classic form", function()
        assert.is_false(predicate.is_expression_input("3"))
        assert.is_false(predicate.is_expression_input("p q r"))
    end)

    it("detects operators, symbols, parens, and separators", function()
        assert.is_true(predicate.is_expression_input("p and q"))
        assert.is_true(predicate.is_expression_input("p ∧ q"))
        assert.is_true(predicate.is_expression_input("!p"))
        assert.is_true(predicate.is_expression_input("(p)"))
        assert.is_true(predicate.is_expression_input("p | q"))
        assert.is_true(predicate.is_expression_input("p, q"))
    end)
end)
