local symbols = require("truth-table.symbols")
local predicate = require("truth-table.predicate")
local core = require("truth-table.core")

describe("symbols", function()
    it("pairs an ascii word with a unicode symbol for every constant", function()
        local expected = {
            NOT = { "not", "¬" }, AND = { "and", "∧" }, OR = { "or", "∨" }, XOR = { "xor", "⊕" },
            IMPLIES = { "implies", "→" }, IFF = { "iff", "⇔" },
            FORALL = { "forall", "∀" }, EXISTS = { "exists", "∃" },
            TOP = { "true", "⊤" }, BOTTOM = { "false", "⊥" }, EQUIV = { "equiv", "≡" },
        }
        for key, pair in pairs(expected) do
            assert.are.same({ ascii = pair[1], unicode = pair[2] }, symbols[key], key)
        end
    end)

    it("is the source of the predicate language's rendered symbols", function()
        for _, key in ipairs({ "NOT", "AND", "OR", "XOR", "IMPLIES", "IFF" }) do
            assert.are.equal(symbols[key].unicode, predicate.SYMBOLS[symbols[key].ascii], key)
        end
    end)

    it("keeps ≡ out of the predicate language", function()
        assert.is_nil(predicate.SYMBOLS.equiv)
        local ast, err = predicate.parse_expression("A ≡ B")
        assert.is_nil(ast)
        assert.is_truthy(err:find("Unexpected character: ≡", 1, true))
        assert.are.equal("A ∧ equiv", core.ast_to_heading(assert(predicate.parse_expression("A and equiv"))))
    end)

    it("renders iff as ⇔ and still parses = as iff", function()
        local ast = assert(predicate.parse_expression("A iff B"))
        assert.are.equal("A ⇔ B", core.ast_to_heading(ast))
        local from_equals = assert(predicate.parse_expression("A = B"))
        assert.are.equal("A ⇔ B", core.ast_to_heading(from_equals))
    end)
end)
