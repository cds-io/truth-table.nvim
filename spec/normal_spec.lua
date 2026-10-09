-- Normal forms: an expression as an ∨ of ∧ terms of literals (disjunctive),
-- or an ∧ of ∨ clauses (conjunctive), tidied.
local normal = require("truth-table.normal")
local predicate = require("truth-table.predicate")
local trees = require("truth-table.trees")
local model = require("truth-table.table_model")

local function dnf(source)
    local tree, err = normal.dnf(assert(predicate.parse_expression(source)))
    return tree and trees.heading(tree), err
end

local function cnf(source)
    local tree, err = normal.cnf(assert(predicate.parse_expression(source)))
    return tree and trees.heading(tree), err
end

describe("normal.dnf", function()
    it("leaves a form alone and distributes ∧ over ∨", function()
        assert.are.equal("(a ∧ b) ∨ c", dnf("(a ∧ b) ∨ c"))
        assert.are.equal("(a ∧ c) ∨ (b ∧ c)", dnf("(a ∨ b) ∧ c"))
        assert.are.equal("(a ∧ c) ∨ (a ∧ d) ∨ (b ∧ c) ∨ (b ∧ d)", dnf("(a ∨ b) ∧ (c ∨ d)"))
    end)

    it("unfolds →, ⊕ and ⇔ first", function()
        assert.are.equal("¬a ∨ b", dnf("a → b"))
        assert.are.equal("(a ∧ b) ∨ (¬a ∧ ¬b)", dnf("a ⇔ b"))
        assert.are.equal("(a ∧ ¬b ∧ c) ∨ (¬a ∧ b ∧ c)", dnf("(a ⊕ b) ∧ c"))
    end)

    it("pushes negations down to the variables", function()
        assert.are.equal("¬a ∨ ¬b", dnf("¬(a ∧ b)"))
        assert.are.equal("¬a ∧ ¬b", dnf("¬(a ∨ b)"))
        assert.are.equal("a ∧ b", dnf("¬¬(a ∧ b)"))
        assert.are.equal("(¬a ∧ b) ∨ (¬b ∧ a)", dnf("¬(a ⇔ b)"))
        assert.are.equal("(a ∧ ¬c) ∨ (b ∧ ¬c)", dnf("¬(¬(a ∨ b) ∨ c)"))
    end)

    it("drops a term that holds a literal and its negation", function()
        assert.are.equal("(a ∧ c) ∨ (b ∧ ¬a) ∨ (b ∧ c)", dnf("(a ∨ b) ∧ (¬a ∨ c)"))
        assert.are.equal("0", dnf("a ∧ ¬a"))
        assert.are.equal("0", dnf("(a ∨ b) ∧ ¬a ∧ ¬b"))
    end)

    it("collapses a repeated literal and a repeated term, and a term another absorbs", function()
        assert.are.equal("a ∧ b", dnf("a ∧ b ∧ a"))
        assert.are.equal("(a ∧ b) ∨ c", dnf("(a ∧ b) ∨ c ∨ (b ∧ a)"))
        assert.are.equal("a", dnf("a ∨ (a ∧ b)"))
        assert.are.equal("a ∨ b", dnf("(a ∨ b) ∧ (a ∨ b ∨ c)"))
    end)

    it("folds constants", function()
        assert.are.equal("a", dnf("a ∧ 1"))
        assert.are.equal("a", dnf("a ∨ 0"))
        assert.are.equal("1", dnf("a ∨ 1"))
        assert.are.equal("0", dnf("a ∧ 0"))
        assert.are.equal("a", dnf("a ∧ ¬0"))
        assert.are.equal("1", dnf("⊤"))
    end)

    it("stops at the form: a ∨ ¬a is a DNF already, and minimising is the map's job", function()
        assert.are.equal("a ∨ ¬a", dnf("a ∨ ¬a"))
        assert.are.equal("(a ∧ b) ∨ (¬a ∧ b)", dnf("(a ∧ b) ∨ (¬a ∧ b)"))
    end)

    it("keeps terms in the order distribution meets them, and literals as met", function()
        assert.are.equal("(b ∧ a) ∨ (b ∧ c)", dnf("b ∧ (a ∨ c)"))
        assert.are.equal("(c ∧ b) ∨ (a ∧ b)", dnf("(c ∨ a) ∧ b"))
    end)

    it("treats a column reference as an atom", function()
        assert.are.equal("(:h1 ∧ a) ∨ (¬:h2 ∧ a)", dnf("(:h1 ∨ ¬:h2) ∧ a"))
    end)

    it("refuses a form of more than 256 terms", function()
        local clauses = {}
        for i = 1, 9 do
            clauses[i] = ("(a%d ∨ b%d)"):format(i, i)
        end
        local form, err = dnf(table.concat(clauses, " ∧ "))
        assert.is_nil(form)
        assert.are.equal("The form would have more than 256 terms", err)
        clauses[9] = nil
        assert.is_truthy(dnf(table.concat(clauses, " ∧ ")))
    end)
end)

describe("normal.cnf", function()
    it("is the dual: ∨ distributed over ∧", function()
        assert.are.equal("(a ∨ b) ∧ c", cnf("(a ∨ b) ∧ c"))
        assert.are.equal("(a ∨ c) ∧ (b ∨ c)", cnf("(a ∧ b) ∨ c"))
        assert.are.equal("¬a ∨ b", cnf("a → b"))
        assert.are.equal("(a ∨ ¬b) ∧ (b ∨ ¬a)", cnf("a ⇔ b"))
        assert.are.equal("(a ∨ b) ∧ (¬b ∨ ¬a)", cnf("a ⊕ b"))
    end)

    it("drops a clause that holds a literal and its negation, and folds constants", function()
        assert.are.equal("(a ∨ c) ∧ (b ∨ ¬a) ∧ (b ∨ c)", cnf("(a ∧ b) ∨ (¬a ∧ c)"))
        assert.are.equal("1", cnf("a ∨ ¬a"))
        assert.are.equal("a ∧ ¬a", cnf("a ∧ ¬a"))
        assert.are.equal("a", cnf("a ∨ 0"))
    end)
end)

describe("a normal form", function()
    local corpus = {
        "a → b", "a ⊕ b ⊕ c", "(a ⇔ b) → (c ∧ ¬a)", "¬(a ∨ (b ∧ ¬(c ∨ a)))",
        "(a ∨ b) ∧ (¬a ∨ c) ∧ (b ∨ c)", "a ∧ (b ∨ c) ∧ (d ∨ e)", "¬(p → q) ∨ (q ⇔ ¬p)",
        "(A ∧ B) ∨ (¬A ∧ C) ∨ (B ∧ C ∧ D)", "⊤ ∧ (a ∨ ⊥)", "a ∧ ¬a ∨ b", "(a → b) ∧ (b → a) ∧ (a ⊕ b)",
    }

    local function agrees(source, form)
        local ast, result = assert(predicate.parse_expression(source)), assert(form)
        local names = assert(predicate.variables(ast))
        for _, row in ipairs(model.generate_rows(#names)) do
            local ctx = {}
            for i, name in ipairs(names) do
                ctx[name] = row[i]
            end
            assert.are.equal(predicate.eval_ast(ast, ctx), predicate.eval_ast(result, ctx), source .. " at row " .. table.concat(row, ""))
        end
    end

    -- Is `node` an `outer` chain of `inner` chains of literals (a variable,
    -- a reference, a constant, or the negation of one)?
    local function shaped(node, outer, inner)
        local function literal(item)
            item = trees.unparen(item)
            if item.type == "not" then
                item = trees.unparen(item.operand)
            end
            return item.type == "var" or item.type == "reference" or item.type == "literal"
        end
        for _, term in ipairs(trees.operands(node, outer)) do
            for _, item in ipairs(trees.operands(term, inner)) do
                if not literal(item) then
                    return false
                end
            end
        end
        return true
    end

    it("equals its source under every assignment, and has the form's shape", function()
        for _, source in ipairs(corpus) do
            local ast = assert(predicate.parse_expression(source))
            local d, c = assert(normal.dnf(ast)), assert(normal.cnf(ast))
            agrees(source, d)
            agrees(source, c)
            assert.is_true(shaped(d, "or", "and"), source .. " as DNF: " .. trees.heading(d))
            assert.is_true(shaped(c, "and", "or"), source .. " as CNF: " .. trees.heading(c))
        end
    end)

    it("is a fixed point: the form of a form is itself", function()
        for _, source in ipairs(corpus) do
            local d = assert(normal.dnf(assert(predicate.parse_expression(source))))
            assert.are.equal(trees.heading(d), trees.heading(assert(normal.dnf(d))))
            local c = assert(normal.cnf(assert(predicate.parse_expression(source))))
            assert.are.equal(trees.heading(c), trees.heading(assert(normal.cnf(c))))
        end
    end)
end)
