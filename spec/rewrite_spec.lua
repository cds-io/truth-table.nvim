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
