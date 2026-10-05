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
        assert.are.equal("A ∧ ¬C", target("∧"))
        assert.are.equal("A ∧ ¬C", target("("))
        assert.are.equal("A ∧ ¬C", target(")"))
        assert.are.equal("G ∧ ¬C", target("∧", 2))
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
        assert.are.equal("S ∨ (¬C ∧ (A ∨ G))", run("factor", "S ∨ A ∧ ¬C ∨ G ∧ ¬C", "¬C"))
    end)

    it("factors ∨ out of ∧ as well", function()
        assert.are.equal("A ∨ (B ∧ C)", run("factor", "(A ∨ B) ∧ (A ∨ C)", "A"))
    end)

    it("keeps multi-operand remainders together", function()
        assert.are.equal("¬C ∧ ((A ∧ B) ∨ G)", run("factor", "A ∧ B ∧ ¬C ∨ G ∧ ¬C", "¬C"))
    end)

    it("puts the new term where the first participating term was", function()
        assert.are.equal("X ∨ (B ∧ (A ∨ C)) ∨ Y", run("factor", "X ∨ A ∧ B ∨ Y ∨ C ∧ B", "B"))
    end)

    it("removes only the first occurrence within a term", function()
        assert.are.equal("A ∧ ((A ∧ B) ∨ C)", run("factor", "A ∧ A ∧ B ∨ A ∧ C", "A"))
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
        assert.are.equal("Fewer than two terms share A ∨ B", err)
    end)
end)

describe("rewrite.distribute", function()
    it("multiplies the target into the group on its right", function()
        assert.are.equal("(¬C ∧ A) ∨ (¬C ∧ G)", run("distribute", "¬C ∧ (A ∨ G)", "¬C"))
    end)

    it("falls back to the group on its left, keeping its side", function()
        assert.are.equal("(A ∧ ¬C) ∨ (G ∧ ¬C)", run("distribute", "(A ∨ G) ∧ ¬C", "¬C"))
    end)

    it("merges into the parent chain, keeping the term's parentheses", function()
        assert.are.equal("S ∨ (¬C ∧ A) ∨ (¬C ∧ G)", run("distribute", "S ∨ (¬C ∧ (A ∨ G))", "¬C"))
        assert.are.equal("S ∨ (¬C ∧ A) ∨ (¬C ∧ G)", run("distribute", "S ∨ ¬C ∧ (A ∨ G)", "¬C"))
        assert.are.equal("(¬C ∧ A) ∨ (¬C ∧ G) ∨ S", run("distribute", "(¬C ∧ (A ∨ G)) ∨ S", "¬C"))
    end)

    it("keeps the products grouped beside other operands", function()
        assert.are.equal("X ∧ ((¬C ∧ A) ∨ (¬C ∧ G))", run("distribute", "X ∧ ¬C ∧ (A ∨ G)", "¬C"))
    end)

    it("distributes a group over a group one step at a time", function()
        assert.are.equal("((A ∨ B) ∧ C) ∨ ((A ∨ B) ∧ D)", run("distribute", "(A ∨ B) ∧ (C ∨ D)", "("))
    end)

    it("distributes ∨ over ∧", function()
        assert.are.equal("(A ∨ B) ∧ (A ∨ C)", run("distribute", "A ∨ (B ∧ C)", "A"))
    end)

    it("keeps the grouping a negation needs", function()
        assert.are.equal("¬((¬C ∧ A) ∨ (¬C ∧ G))", run("distribute", "¬(¬C ∧ (A ∨ G))", "¬C"))
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

describe("rewrite.xor", function()
    it("recognises an exclusive or written as a sum of two products", function()
        assert.are.equal("T ⊕ E", run("xor", "¬T ∧ E ∨ T ∧ ¬E", "¬T"))
        assert.are.equal("R ∧ (T ⊕ E)", run("xor", "R ∧ ((¬T ∧ E) ∨ (T ∧ ¬E))", "¬T"))
    end)

    it("gives the same result from either term, and from a term's operator", function()
        local source = "R ∧ ((¬T ∧ E) ∨ (T ∧ ¬E))"
        assert.are.equal("R ∧ (T ⊕ E)", run("xor", source, "¬E"))
        assert.are.equal("R ∧ (T ⊕ E)", run("xor", source, "∧", 3))
    end)

    it("recognises an equivalence when both operands flip together", function()
        assert.are.equal("A ⇔ B", run("xor", "A ∧ B ∨ ¬A ∧ ¬B", "A"))
        assert.are.equal("A ⇔ B", run("xor", "¬A ∧ ¬B ∨ A ∧ B", "B", 2))
    end)

    it("matches the partner's operands in either order", function()
        assert.are.equal("A ⊕ B", run("xor", "¬A ∧ B ∨ ¬B ∧ A", "¬A"))
    end)

    it("leaves the other terms in place and parenthesises the result beside them", function()
        assert.are.equal("(A ⊕ B) ∨ (A ∧ C)", run("xor", "¬A ∧ B ∨ A ∧ ¬B ∨ A ∧ C", "¬A"))
        assert.are.equal("X ∨ (A ⊕ B) ∨ Y", run("xor", "X ∨ ¬A ∧ B ∨ Y ∨ A ∧ ¬B", "¬B"))
    end)

    it("recognises the product-of-sums forms", function()
        assert.are.equal("A ⊕ B", run("xor", "(A ∨ B) ∧ (¬A ∨ ¬B)", "A"))
        assert.are.equal("A ⇔ B", run("xor", "(¬A ∨ B) ∧ (A ∨ ¬B)", "B"))
    end)

    it("treats a compound operand as one operand, parentheses ignored", function()
        assert.are.equal("(P → Q) ⊕ R", run("xor", "¬(P → Q) ∧ R ∨ (P → Q) ∧ ¬R", "R"))
    end)

    it("refuses when no pair of two-operand terms are complements of each other", function()
        for _, case in ipairs({
            { "A ∧ B ∨ A ∧ C", "A" },
            { "¬A ∧ B ∨ A ∧ B", "B" },
            { "¬A ∧ B ∧ R ∨ A ∧ ¬B ∧ R", "R" },
            { "A ⊕ B", "A" },
            { "¬A ∧ B", "B" },
        }) do
            local out, err = run("xor", case[1], case[2])
            assert.is_nil(out, case[1])
            assert.are.equal("No pair of terms under the cursor forms ⊕ or ⇔", err)
        end
    end)

    it("needs an operand under the cursor", function()
        local out, err = run("xor", "¬T ∧ E ∨ T ∧ ¬E", "∨")
        assert.is_nil(out)
        assert.are.equal("Put the cursor on an operand", err)
    end)
end)

describe("rewrite.de_morgan", function()
    it("contracts the nearest enclosing pair of negations", function()
        assert.are.equal("R ∧ (T ∨ E) ∧ ¬(T ∧ E)", run("de_morgan", "R ∧ (T ∨ E) ∧ (¬T ∨ ¬E)", "¬T"))
        assert.are.equal("¬(A ∧ B) ∨ C", run("de_morgan", "¬A ∨ ¬B ∨ C", "¬A"))
    end)

    it("expands the nearest enclosing negated group", function()
        assert.are.equal("A ∨ ¬B ∨ ¬C", run("de_morgan", "A ∨ ¬(B ∧ C)", "¬"))
        assert.are.equal("A ∧ (¬B ∨ ¬C)", run("de_morgan", "A ∧ ¬(B ∧ C)", "B"))
    end)

    it("prefers the innermost match, so the cursor chooses between nested ones", function()
        assert.are.equal("¬¬(A ∧ B)", run("de_morgan", "¬(¬A ∨ ¬B)", "A"))
        assert.are.equal("¬¬A ∧ ¬¬B", run("de_morgan", "¬(¬A ∨ ¬B)", "¬"))
    end)

    it("rewrites the whole expression when there is no cursor or it is outside", function()
        local source = "not (A and B)"
        local ast = assert(predicate.parse_located(source))
        assert.are.equal("¬A ∨ ¬B", predicate.ast_to_heading(assert(rewrite.de_morgan(ast, nil))))
        assert.are.equal("¬A ∨ ¬B", predicate.ast_to_heading(assert(rewrite.de_morgan(ast, 0))))
        assert.are.equal("¬A ∨ ¬B", predicate.ast_to_heading(assert(rewrite.de_morgan(ast, #source + 5))))
    end)

    it("refuses when nothing from the cursor up to the root matches", function()
        local out, err = run("de_morgan", "A ∨ ¬(B ∧ C)", "A")
        assert.is_nil(out)
        assert.are.equal("No De Morgan rewrite applies under the cursor or to the whole expression", err)
    end)
end)

describe("rewrite.simplify", function()
    -- The rewritten text and the law that was applied.
    local function simplify(source, needle, occurrence)
        local ast = assert(predicate.parse_located(source))
        local tree, law = rewrite.simplify(ast, needle and byte_of(source, needle, occurrence))
        if not tree then
            return nil, law
        end
        return predicate.ast_to_heading(tree), law
    end

    local function check(cases)
        for _, case in ipairs(cases) do
            local text, law = simplify(case[1], case[2], case[5])
            assert.are.same({ case[3], case[4] }, { text, law }, case[1] .. " at " .. tostring(case[2]))
        end
    end

    it("collapses an operand and its negation to a constant", function()
        check({
            { "a ∨ ¬a", "a", "1", "complement" },
            { "a ∧ ¬a", "¬", "0", "complement" },
            { "b ∧ (a ∨ ¬a)", "a", "b ∧ 1", "complement" },
            { "¬a ∨ b ∨ a", "a", "1 ∨ b", "complement" },
            { "(p ∧ q) ∨ ¬(p ∧ q)", "p", "1", "complement" },
        })
    end)

    it("applies the constant laws, keeping a typed constant's spelling", function()
        check({
            { "b ∧ 1", "1", "b", "identity" },
            { "0 ∨ a ∨ b", "0", "a ∨ b", "identity" },
            { "c ∧ (a ∨ 0)", "0", "c ∧ a", "identity" },
            { "(a ∨ b) ∧ 1", "1", "a ∨ b", "identity" },
            { "a ∨ 1", "a", "1", "domination" },
            { "a ∧ b ∧ ⊥", "b", "⊥", "domination" },
            { "c ∨ (a ∧ 0)", "a", "c ∨ 0", "domination" },
            { "a ∨ a", "a", "a", "idempotence" },
            { "a ∧ b ∧ a", "a", "a ∧ b", "idempotence" },
            { "(a ∧ b) ∨ (b ∧ a)", "a", "a ∧ b", "idempotence" },
        })
    end)

    it("absorbs the terms that contain the operand under the cursor", function()
        check({
            { "a ∨ (a ∧ b)", "a", "a", "absorption" },
            { "a ∧ (a ∨ b)", "a", "a", "absorption" },
            { "a ∨ a ∧ b ∨ c ∨ a ∧ d", "a", "a ∨ c", "absorption" },
            { "a ∧ b ∨ a ∧ b ∧ c", "a", "a ∧ b", "absorption" },
            { "a ∨ (a ∧ b)", "b", "a", "absorption" },
        })
    end)

    it("drops the negated operand from the terms beside it", function()
        check({
            { "a ∨ (¬a ∧ b)", "a", "a ∨ b", "absorption" },
            { "a ∧ (¬a ∨ b)", "a", "a ∧ b", "absorption" },
            { "¬a ∨ a ∧ b ∧ c", "¬", "¬a ∨ (b ∧ c)", "absorption" },
            { "a ∨ (¬a ∧ b ∧ c)", "b", "a ∨ (b ∧ c)", "absorption" },
        })
    end)

    it("merges two terms that differ in one complemented operand", function()
        check({
            { "(a ∧ b) ∨ (¬a ∧ b)", "b", "b", "reduction" },
            { "(a ∨ b) ∧ (¬a ∨ b)", "b", "b", "reduction" },
            { "a ∧ b ∧ c ∨ c ∧ ¬a ∧ b ∨ d", "c", "(b ∧ c) ∨ d", "reduction" },
            { "(a ∧ b ∧ c) ∨ (a ∧ ¬b ∧ c) ∨ d", "b", "(a ∧ c) ∨ d", "reduction" },
        })
    end)

    it("removes negations of constants and double negations", function()
        check({
            { "¬1", "1", "0", "negation" },
            { "a ∨ ¬⊥", "⊥", "a ∨ ⊤", "negation" },
            { "¬¬a", "a", "a", "double negation" },
            { "b ∧ ¬¬(a ∨ c)", "¬", "b ∧ (a ∨ c)", "double negation" },
            { "¬¬(a ∨ c)", "¬", "a ∨ c", "double negation" },
        })
    end)

    it("prefers a match involving the operand under the cursor", function()
        check({
            { "a ∨ a ∧ b ∨ c ∨ c ∧ d", "c", "a ∨ (a ∧ b) ∨ c", "absorption" },
            { "a ∨ a ∧ b ∨ c ∨ c ∧ d", "a", "a ∨ c ∨ (c ∧ d)", "absorption" },
            { "(a ∨ ¬a) ∧ (b ∨ ¬b)", "b", "(a ∨ ¬a) ∧ 1", "complement" },
        })
    end)

    it("looks inside a group the cursor selects, then around it, then anywhere", function()
        check({
            { "(a ∨ ¬a) ∧ (a ∨ b)", "(", "1 ∧ (a ∨ b)", "complement" },
            { "c ∧ (a ∨ 1)", "a", "c ∧ 1", "domination" },
            { "c ∧ (a ∨ 1)", "c", "c ∧ 1", "domination" },
            { "(a ∧ 1) ∨ (b ∧ 1)", "∨", "a ∨ (b ∧ 1)", "identity" },
        })
        local text, law = simplify("a ∨ ¬a")
        assert.are.same({ "1", "complement" }, { text, law })
    end)

    it("refuses when no collapsing law applies", function()
        for _, source in ipairs({ "a", "a ∨ b", "a ∧ (b ∨ c)", "a ⊕ a", "a → a", "(a ∧ b) ∨ (¬a ∧ c)" }) do
            local text, err = simplify(source, "a")
            assert.is_nil(text, source)
            assert.are.equal("No simplification applies to this expression", err)
        end
    end)
end)

-- The whole menu for one expression, as { law, text } pairs in order.
describe("rewrite.moves", function()
    local function moves(source)
        local listed = {}
        for i, move in ipairs(rewrite.moves(assert(predicate.parse_located(source)))) do
            listed[i] = { move.law, move.text }
        end
        return listed
    end

    it("lists one entry per result, however many operands lead to it", function()
        assert.are.same({ { "commutativity", "B ∧ A" } }, moves("A ∧ B"))
    end)

    it("leaves out a rewrite that gives the expression back", function()
        assert.are.same({ { "idempotence", "A" } }, moves("A ∧ A"))
    end)

    it("has nothing for an expression no law applies to", function()
        assert.are.same({}, moves("A"))
        assert.are.same({}, moves("A → B"))
    end)

    it("lists the collapsing laws Simplify passes over for a nearer one", function()
        local source = "A ∨ ¬A ∨ A"
        local ast = assert(predicate.parse_located(source))
        assert.are.equal("1 ∨ A", predicate.ast_to_heading(assert(rewrite.simplify(ast))))
        assert.are.same({
            { "complement", "1 ∨ A" },
            { "idempotence", "A ∨ ¬A" },
            { "complement", "A ∨ 1" },
            { "commutativity", "¬A ∨ A ∨ A" },
            { "commutativity", "A ∨ A ∨ ¬A" },
        }, moves(source))
    end)

    local function results(source, law)
        local found = {}
        for _, move in ipairs(moves(source)) do
            if move[1] == law then
                found[#found + 1] = move[2]
            end
        end
        return found
    end

    it("distributes into either neighbouring group, retaining the cursor preference", function()
        local source = "(A ∨ B) ∧ C ∧ (D ∨ E)"
        local expected = {
            "(A ∨ B) ∧ ((C ∧ D) ∨ (C ∧ E))",
            "((A ∧ C) ∨ (B ∧ C)) ∧ (D ∨ E)",
        }
        assert.are.same(expected, results(source, "distributivity (distributing)"))
        local ast = assert(predicate.parse_located(source))
        assert.are.equal(expected[1], predicate.ast_to_heading(assert(rewrite.distribute(ast, (source:find("C"))))))
    end)

    it("lists every complementary pair, including later repeated operands", function()
        assert.are.same({
            "1 ∨ A ∨ ¬A", "1 ∨ ¬A ∨ A", "A ∨ 1 ∨ ¬A", "A ∨ ¬A ∨ 1",
        }, results("A ∨ ¬A ∨ A ∨ ¬A", "complement"))
    end)

    it("lists every duplicate and reduction partner", function()
        assert.are.same({ "A ∨ B ∨ A", "A ∨ A ∨ B" }, results("A ∨ A ∨ B ∨ A", "idempotence"))
        assert.are.same({
            "B ∨ C ∨ (¬A ∧ B)", "B ∨ (¬A ∧ B) ∨ C",
        }, results("(A ∧ B) ∨ (¬A ∧ B) ∨ C ∨ (¬A ∧ B)", "reduction"))
    end)

    it("recognises each complementary partner, without changing the input", function()
        assert.are.same({
            "(A ⇔ B) ∨ C ∨ (¬A ∧ ¬B)", "(A ⇔ B) ∨ (¬A ∧ ¬B) ∨ C",
        }, results("(A ∧ B) ∨ (¬A ∧ ¬B) ∨ C ∨ (¬A ∧ ¬B)", "definition of ⇔"))
    end)

    it("orders the families: the shrinking laws first, the swaps last", function()
        assert.are.same({
            { "reduction", "b" },
            { "distributivity (factoring)", "b ∧ (a ∨ ¬a)" },
            { "distributivity (distributing)", "((a ∧ b) ∨ ¬a) ∧ ((a ∧ b) ∨ b)" },
            { "distributivity (distributing)", "(a ∨ (¬a ∧ b)) ∧ (b ∨ (¬a ∧ b))" },
            { "commutativity", "(¬a ∧ b) ∨ (a ∧ b)" },
            { "commutativity", "(b ∧ a) ∨ (¬a ∧ b)" },
            { "commutativity", "(a ∧ b) ∨ (b ∧ ¬a)" },
        }, moves("(a and b) or (not a and b)"))
    end)

    it("applies De Morgan at every node, the outermost first", function()
        assert.are.same({
            { "De Morgan", "¬A ∨ ¬B" },
            { "commutativity", "¬(B ∧ A)" },
        }, moves("¬(A ∧ B)"))
        local found = {}
        for _, move in ipairs(moves("¬(A ∧ B) ∧ ¬(C ∨ D)")) do
            if move[1] == "De Morgan" then
                found[#found + 1] = move[2]
            end
        end
        assert.are.same({
            "¬((A ∧ B) ∨ C ∨ D)",
            "(¬A ∨ ¬B) ∧ ¬(C ∨ D)",
            "¬(A ∧ B) ∧ ¬C ∧ ¬D",
        }, found)
    end)

    it("recognises ⊕ spelled out as two terms", function()
        assert.are.same({ "definition of ⊕", "T ⊕ E" }, moves("(¬T ∧ E) ∨ (T ∧ ¬E)")[1])
    end)

    it("returns each move's tree, canonical and without spans", function()
        local move = rewrite.moves(assert(predicate.parse_located("A ∧ B")))[1]
        assert.are.equal("B ∧ A", predicate.ast_to_heading(move.tree))
        assert.is_nil(move.tree.span)
    end)
end)

-- Every rewrite, at every cursor byte of every expression here, either refuses
-- with a message or returns a tree that means the same, and whose rendered
-- text (what lands in the buffer) parses back to that same function. The
-- input is never modified.
describe("rewrite soundness", function()
    local corpus = {
        "(A ∨ B) ∧ C ∧ (D ∨ E)",
        "A ∨ ¬A ∨ A ∨ ¬A",
        "A ∨ A ∨ B ∨ A",
        "(A ∧ B) ∨ (¬A ∧ B) ∨ C ∨ (¬A ∧ B)",
        "(A ∧ B) ∨ (¬A ∧ ¬B) ∨ C ∨ (¬A ∧ ¬B)",
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
        "R ∧ ((¬T ∧ E) ∨ (T ∧ ¬E))",
        "(A ∨ B) ∧ (¬A ∨ ¬B) ∧ ¬(C ∧ ¬A)",
        "A ∧ B ∨ ¬A ∧ ¬B ∨ ¬(¬A ∨ ¬C)",
        "A ∧ ⊤ ∨ ⊥ ∧ A ∨ 1 ∧ (B ∨ ⊥)",
        "A ∨ A ∧ B ∨ ¬A ∧ C ∨ (B ∧ ¬C ∧ A) ∨ B ∧ C ∧ A",
        "(A ∨ B) ∧ (¬A ∨ B) ∧ (A ∨ ¬A ∨ C) ∧ ¬¬B ∧ ¬0",
        "A ∧ A ∨ A ∧ B ∨ ¬(A ∧ A) ∧ C ∨ B ∧ A",
        "¬(A ∨ ¬A) ∨ (B → B ∧ (C ∨ ¬C)) ∨ (A ⊕ (B ∨ B))",
    }
    local rewrites = {
        factor = function(ast, byte) return rewrite.factor(ast, byte) end,
        distribute = function(ast, byte) return rewrite.distribute(ast, byte) end,
        commute = function(ast, byte) return rewrite.commute(ast, byte, false) end,
        commute_back = function(ast, byte) return rewrite.commute(ast, byte, true) end,
        xor = function(ast, byte) return rewrite.xor(ast, byte) end,
        de_morgan = function(ast, byte) return rewrite.de_morgan(ast, byte) end,
        simplify = function(ast, byte) return rewrite.simplify(ast, byte) end,
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

    it("lists only moves that preserve meaning, each once", function()
        local listed = 0
        for _, source in ipairs(corpus) do
            local ast = assert(predicate.parse_located(source))
            local before = predicate.ast_to_heading(ast)
            local variables = inputs(ast)
            local seen = { [before] = true }
            for _, move in ipairs(rewrite.moves(ast)) do
                listed = listed + 1
                local where = move.law .. " of " .. source .. " gave " .. move.text
                assert.is_nil(seen[move.text], where)
                seen[move.text] = true
                assert.are.equal(move.text, predicate.ast_to_heading(move.tree), where)
                assert.is_true(same_function(ast, move.tree, variables), where)
                local reparsed = assert(predicate.parse_expression(move.text), where)
                assert.are.equal(move.text, predicate.ast_to_heading(reparsed), where)
                assert.is_nil(move.tree.span, where)
            end
            assert.are.equal(before, predicate.ast_to_heading(ast), source)
        end
        assert.is_true(listed > 200, "only " .. listed .. " moves listed")
    end)

    -- The menu is at least the keys: whatever a rewrite command gives from
    -- some cursor position is an entry, unless it gives the expression back.
    it("lists whatever a cursor rewrite reaches from any byte", function()
        for _, source in ipairs(corpus) do
            local ast = assert(predicate.parse_located(source))
            local listed = { [predicate.ast_to_heading(ast)] = true }
            for _, move in ipairs(rewrite.moves(ast)) do
                listed[move.text] = true
            end
            for byte = 0, #source + 1 do
                for name, fn in pairs(rewrites) do
                    local tree = fn(ast, byte)
                    if tree then
                        local text = predicate.ast_to_heading(tree)
                        assert.is_true(listed[text], name .. " at byte " .. byte .. " of " .. source .. " gave " .. text)
                    end
                end
            end
        end
    end)
end)
