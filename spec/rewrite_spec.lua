local predicate = require("truth-table.predicate")
local rewrite = require("truth-table.rewrite")

-- Byte of the `occurrence`-th appearance of `needle` in `source`: the cursor.
local function byte_of(source, needle, occurrence)
    local from, found = 1, nil
    for _ = 1, occurrence or 1 do
        found = assert(source:find(needle, from, true), needle .. " not in " .. source)
        from = found + 1
    end
    return found
end

-- Run one rewrite with the cursor on `needle`; returns rendered text, or nil
-- and the refusal message.
local function run(name, source, needle, occurrence, backward)
    local ast = assert(predicate.parse_located(source))
    local tree, err = rewrite[name](ast, byte_of(source, needle, occurrence), backward)
    if not tree then
        return nil, err
    end
    return predicate.ast_to_heading(tree)
end

describe("rewrite.target", function()
    local source = "S ∨ (A ∧ ¬C) ∨ (G ∧ ¬C)"
    local function target(needle, occurrence)
        local ast = assert(predicate.parse_located(source))
        local node, err = rewrite.target(ast, byte_of(source, needle, occurrence))
        if not node then
            return nil, err
        end
        return predicate.ast_to_heading(node)
    end

    it("widens to the nearest chain operand", function()
        assert.are.equal("¬C", target("C"))
        assert.are.equal("¬C", target("¬"))
        assert.are.equal("A", target("A"))
        assert.are.equal("S", target("S"))
    end)

    it("takes a whole group from its operator or parentheses", function()
        assert.are.equal("(A ∧ ¬C)", target("∧"))
        assert.are.equal("(A ∧ ¬C)", target("("))
        assert.are.equal("(A ∧ ¬C)", target(")"))
        assert.are.equal("(G ∧ ¬C)", target("∧", 2))
    end)

    it("has no target on the root chain's operators or outside the expression", function()
        local node, err = target("∨")
        assert.is_nil(node)
        assert.are.equal("Put the cursor on an operand", err)
        assert.is_nil(target("∨", 2))
        local ast = assert(predicate.parse_located(source))
        assert.is_nil(rewrite.target(ast, 0))
        assert.is_nil(rewrite.target(ast, #source + 1))
    end)

    it("lands on the first byte of a multibyte symbol and on its last", function()
        local ast = assert(predicate.parse_located("A ∧ ¬C"))
        local first = byte_of("A ∧ ¬C", "¬")
        assert.are.equal("¬C", predicate.ast_to_heading(assert(rewrite.target(ast, first))))
        assert.are.equal("¬C", predicate.ast_to_heading(assert(rewrite.target(ast, first + 1))))
    end)

    it("treats a single variable or a negation as having no chain", function()
        for _, lone in ipairs({ "A", "¬A", "A → B" }) do
            assert.is_nil(rewrite.target(assert(predicate.parse_located(lone)), 1))
        end
    end)
end)

describe("rewrite.commute", function()
    it("swaps the target with the operand on its right", function()
        assert.are.equal("(¬C ∧ (A ∨ G)) ∨ S", run("commute", "S ∨ (¬C ∧ (A ∨ G))", "S"))
        assert.are.equal("B ∧ A ∧ C", run("commute", "A ∧ B ∧ C", "A"))
    end)

    it("flips direction at either end of the chain", function()
        assert.are.equal("A ∧ C ∧ B", run("commute", "A ∧ B ∧ C", "C"))
        assert.are.equal("B ∧ A ∧ C", run("commute", "A ∧ B ∧ C", "A", 1, true))
    end)

    it("swaps leftward when asked", function()
        assert.are.equal("B ∧ A ∧ C", run("commute", "A ∧ B ∧ C", "B", 1, true))
    end)

    it("works on xor and iff chains, and inside a negation", function()
        assert.are.equal("B ⊕ A", run("commute", "A xor B", "A"))
        assert.are.equal("B ⇔ A", run("commute", "A iff B", "B"))
        assert.are.equal("¬(B ∧ A)", run("commute", "not (A and B)", "A"))
    end)

    it("leaves implication alone", function()
        local out, err = run("commute", "A → B", "A")
        assert.is_nil(out)
        assert.are.equal("Put the cursor on an operand", err)
    end)

    it("reads through parentheses around the same operator and renders flat", function()
        assert.are.equal("B ∨ A ∨ C", run("commute", "A ∨ (B ∨ C)", "A"))
    end)

    it("moves references and literals like any operand", function()
        assert.are.equal("1 ∧ :h2", run("commute", ":h2 and 1", ":h2"))
    end)
end)

describe("rewrite.factor", function()
    it("pulls a shared operand out of the terms that have it", function()
        assert.are.equal("S ∨ (¬C ∧ (A ∨ G))", run("factor", "S ∨ (A ∧ ¬C) ∨ (G ∧ ¬C)", "¬C"))
        assert.are.equal("S ∨ (¬C ∧ (A ∨ G))", run("factor", "S ∨ (A ∧ ¬C) ∨ (G ∧ ¬C)", "¬C", 2))
        assert.are.equal("S ∨ ¬C ∧ (A ∨ G)", run("factor", "S ∨ A ∧ ¬C ∨ G ∧ ¬C", "¬C"))
    end)

    it("factors ∨ out of ∧ as well", function()
        assert.are.equal("A ∨ (B ∧ C)", run("factor", "(A ∨ B) ∧ (A ∨ C)", "A"))
    end)

    it("keeps multi-operand remainders together", function()
        assert.are.equal("¬C ∧ (A ∧ B ∨ G)", run("factor", "A ∧ B ∧ ¬C ∨ G ∧ ¬C", "¬C"))
    end)

    it("puts the new term where the first participating term was", function()
        assert.are.equal("X ∨ B ∧ (A ∨ C) ∨ Y", run("factor", "X ∨ A ∧ B ∨ Y ∨ C ∧ B", "B"))
    end)

    it("removes only the first occurrence within a term", function()
        assert.are.equal("A ∧ (A ∧ B ∨ C)", run("factor", "A ∧ A ∧ B ∨ A ∧ C", "A"))
    end)

    it("matches the factor with parentheses ignored", function()
        assert.are.equal("¬C ∧ (A ∨ G)", run("factor", "A ∧ ¬C ∨ G ∧ ¬(C)", "¬C"))
    end)

    it("leaves a term that is exactly the factor where it is", function()
        local out, err = run("factor", "A ∨ A ∧ B", "A", 2)
        assert.is_nil(out)
        assert.are.equal("Fewer than two terms share A", err)
    end)

    it("refuses when only one term has the factor", function()
        local out, err = run("factor", "S ∨ A ∧ ¬C ∨ G ∧ D", "¬C")
        assert.is_nil(out)
        assert.are.equal("Fewer than two terms share ¬C", err)
    end)

    it("refuses without an inner and outer chain of dual operators", function()
        for _, case in ipairs({
            { "S ∨ A ∧ ¬C", "S", "Nothing to factor S out of" },
            { "A ∧ B", "A", "Nothing to factor A out of" },
            { "A ∧ B ⊕ A ∧ C", "A", "Nothing to factor A out of" },
            { "(A ⊕ B) ∨ (A ⊕ C)", "A", "Nothing to factor A out of" },
        }) do
            local out, err = run("factor", case[1], case[2])
            assert.is_nil(out, case[1])
            assert.are.equal(case[3], err)
        end
    end)

    it("is order-sensitive about the factor's own shape", function()
        local out, err = run("factor", "(A ∨ B) ∧ C ∨ (B ∨ A) ∧ D", "(")
        assert.is_nil(out)
        assert.are.equal("Fewer than two terms share (A ∨ B)", err)
    end)
end)

describe("rewrite.distribute", function()
    it("multiplies the target into the group on its right", function()
        assert.are.equal("¬C ∧ A ∨ ¬C ∧ G", run("distribute", "¬C ∧ (A ∨ G)", "¬C"))
    end)

    it("falls back to the group on its left, keeping its side", function()
        assert.are.equal("A ∧ ¬C ∨ G ∧ ¬C", run("distribute", "(A ∨ G) ∧ ¬C", "¬C"))
    end)

    it("merges into the parent chain, keeping the term's parentheses", function()
        assert.are.equal("S ∨ (¬C ∧ A) ∨ (¬C ∧ G)", run("distribute", "S ∨ (¬C ∧ (A ∨ G))", "¬C"))
        assert.are.equal("S ∨ ¬C ∧ A ∨ ¬C ∧ G", run("distribute", "S ∨ ¬C ∧ (A ∨ G)", "¬C"))
        assert.are.equal("(¬C ∧ A) ∨ (¬C ∧ G) ∨ S", run("distribute", "(¬C ∧ (A ∨ G)) ∨ S", "¬C"))
    end)

    it("keeps the products grouped beside other operands", function()
        assert.are.equal("X ∧ (¬C ∧ A ∨ ¬C ∧ G)", run("distribute", "X ∧ ¬C ∧ (A ∨ G)", "¬C"))
    end)

    it("distributes a group over a group one step at a time", function()
        assert.are.equal("(A ∨ B) ∧ C ∨ (A ∨ B) ∧ D", run("distribute", "(A ∨ B) ∧ (C ∨ D)", "("))
    end)

    it("distributes ∨ over ∧", function()
        assert.are.equal("(A ∨ B) ∧ (A ∨ C)", run("distribute", "A ∨ (B ∧ C)", "A"))
    end)

    it("keeps the grouping a negation needs", function()
        assert.are.equal("¬(¬C ∧ A ∨ ¬C ∧ G)", run("distribute", "¬(¬C ∧ (A ∨ G))", "¬C"))
    end)

    it("refuses without a neighbouring dual group", function()
        for _, case in ipairs({
            { "A ∧ B", "A", "A" },
            { "A ∧ B ∧ (C ∨ D)", "A", "A" },
            { "¬C ∧ (A ∨ G)", "A", "A" },
            { "A ⊕ (B ∨ C)", "A", "A" },
        }) do
            local out, err = run("distribute", case[1], case[2])
            assert.is_nil(out, case[1])
            assert.are.equal("No neighbouring group to distribute " .. case[3] .. " into", err)
        end
    end)
end)

-- Every rewrite, at every cursor byte of every expression here, either refuses
-- with a message or returns a tree that means the same, and whose rendered
-- text (what lands in the buffer) parses back to that same function. The
-- input is never modified.
describe("rewrite soundness", function()
    local corpus = {
        "S ∨ (A ∧ ¬C) ∨ (G ∧ ¬C)",
        "S ∨ A ∧ ¬C ∨ G ∧ ¬C",
        "(A ∨ B) ∧ (A ∨ C) ∧ D",
        "A ∧ (B ∨ C) ∧ (D ∨ E)",
        "¬(A ∧ (B ∨ ¬C)) ∨ A ∧ B",
        "A ∨ (B ∨ C) ∧ (A ∨ (D ∧ E))",
        "(A → B) ∧ C ∨ (A → B) ∧ D",
        "A ⊕ B ∧ (C ∨ D) ⊕ C",
        "A ⇔ (B ∨ C ∧ A) ⇔ B",
        "((A ∧ B)) ∨ (A ∧ (C ∨ (B ∧ D)))",
        "A ∧ A ∧ B ∨ A ∧ C ∨ 1 ∧ A",
        "not (A and B) or not (A and C)",
        ":h1 ∧ A ∨ :h1 ∧ :h2 ∨ 0 ∧ A",
    }
    local rewrites = {
        factor = function(ast, byte) return rewrite.factor(ast, byte) end,
        distribute = function(ast, byte) return rewrite.distribute(ast, byte) end,
        commute = function(ast, byte) return rewrite.commute(ast, byte, false) end,
        commute_back = function(ast, byte) return rewrite.commute(ast, byte, true) end,
    }

    -- Every input a tree reads: variable names and :hN indices. eval_ast looks
    -- both up in the one assignment table.
    local function inputs(node, found, seen)
        found, seen = found or {}, seen or {}
        local key = node.type == "var" and node.name or node.type == "reference" and node.index
        if key and not seen[key] then
            seen[key] = true
            found[#found + 1] = key
        end
        for _, field in ipairs({ "expr", "operand", "left", "right" }) do
            if node[field] then
                inputs(node[field], found, seen)
            end
        end
        return found
    end

    local function same_function(a, b, variables)
        for row = 0, 2 ^ #variables - 1 do
            local assignment = {}
            for i, name in ipairs(variables) do
                assignment[name] = math.floor(row / 2 ^ (i - 1)) % 2
            end
            if predicate.eval_ast(a, assignment) ~= predicate.eval_ast(b, assignment) then
                return false
            end
        end
        return true
    end

    it("refuses or preserves meaning at every cursor position", function()
        local rewritten = 0
        for _, source in ipairs(corpus) do
            local ast = assert(predicate.parse_located(source))
            local before = predicate.ast_to_heading(ast)
            local variables = inputs(ast)
            for byte = 0, #source + 1 do
                for name, fn in pairs(rewrites) do
                    local where = name .. " at byte " .. byte .. " of " .. source
                    local tree, err = fn(ast, byte)
                    if tree then
                        rewritten = rewritten + 1
                        local text = predicate.ast_to_heading(tree)
                        assert.is_true(same_function(ast, tree, variables), where .. " gave " .. text)
                        local reparsed = assert(predicate.parse_expression(text), where)
                        assert.are.equal(text, predicate.ast_to_heading(reparsed), where)
                        assert.is_true(same_function(ast, reparsed, variables), where .. " rendered as " .. text)
                        assert.is_nil(tree.span, where)
                    else
                        assert.is_string(err, where)
                    end
                    assert.are.equal(before, predicate.ast_to_heading(ast), where)
                end
            end
        end
        -- Guards the property against a rewrite that silently refuses everything.
        assert.is_true(rewritten > 200, "only " .. rewritten .. " rewrites ran")
    end)
end)
