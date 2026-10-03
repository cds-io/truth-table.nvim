local derivation = require("truth-table.derivation")
local markdown = require("truth-table.markdown")

describe("derivation.working_side", function()
    it("is the whole line when there is no separator", function()
        local side = assert(derivation.working_side("  A ∧ B  ", 1))
        assert.are.same({ text = "A ∧ B", first = 3, last = 9 }, side)
    end)

    it("is the side holding the cursor", function()
        local line = "F ≡ A ∨ B ≡ B ∨ A"
        assert.are.equal("F", assert(derivation.working_side(line, 1)).text)
        local middle = assert(derivation.working_side(line, (line:find("A", 1, true))))
        assert.are.equal("A ∨ B", middle.text)
        assert.are.equal("A ∨ B", line:sub(middle.first, middle.last))
        local last = assert(derivation.working_side(line, #line))
        assert.are.equal("B ∨ A", last.text)
        assert.are.equal("B ∨ A", line:sub(last.first, last.last))
    end)

    it("gives the separator, and the padding before a leading one, to the side on the right", function()
        local line = "    ≡ S ∨ T"
        for _, byte in ipairs({ 1, 4, 5, 6, 7 }) do
            assert.are.equal("S ∨ T", assert(derivation.working_side(line, byte)).text, byte)
        end
        local head = "F ≡ A"
        assert.are.equal("A", assert(derivation.working_side(head, (head:find("≡", 1, true)))).text)
        assert.are.equal("G", assert(derivation.working_side("F ≡   ≡ G", 6)).text)
    end)

    it("reports a line or side with no expression", function()
        for _, case in ipairs({ { "", 1 }, { "   ", 2 }, { "F ≡ ", 5 }, { "F ≡   ≡ ", 6 } }) do
            local side, err = derivation.working_side(case[1], case[2])
            assert.is_nil(side, case[1])
            assert.are.equal("No expression under the cursor", err)
        end
    end)
end)

describe("derivation.replace", function()
    it("rewrites one side and keeps the rest of the line byte for byte", function()
        local line = "\t F  ≡  A ∨ B   ≡ C  "
        local side = assert(derivation.working_side(line, (line:find("A", 1, true))))
        assert.are.equal("\t F  ≡  B ∨ A   ≡ C  ", derivation.replace(line, side, "B ∨ A"))
    end)
end)

describe("derivation.step", function()
    local width = markdown.display_width

    it("starts at the indentation of a line with no separator", function()
        local step, column = derivation.step("  S ∨ T", "T ∨ S", width)
        assert.are.equal("  ≡ T ∨ S", step)
        assert.are.equal(#"  ≡ ", column)
        assert.are.equal("T ∨ S", step:sub(column + 1))
    end)

    it("aligns under the last separator by display column, whatever the byte count", function()
        local head = "S ∨ (A ∧ ¬C) ∨ (G ∧ ¬C) ≡ S ∨ A ∧ ¬C ∨ G ∧ ¬C"
        local step = derivation.step(head, "S ∨ ¬C ∧ (A ∨ G)", width)
        assert.are.equal("                        ≡ S ∨ ¬C ∧ (A ∨ G)", step)
        assert.are.equal(width(head:sub(1, (head:find("≡", 1, true)) - 1)), width(step:sub(1, (step:find("≡", 1, true)) - 1)))
    end)

    it("continues a chain from a continuation line", function()
        local step = derivation.step("      ≡ A ∨ B", "B ∨ A", width)
        assert.are.equal("      ≡ B ∨ A", step)
    end)

    it("uses the last separator of a line that has several", function()
        local step = derivation.step("F ≡ A ≡ B", "C", width)
        assert.are.equal("      ≡ C", step)
    end)

    it("copies leading whitespace verbatim", function()
        local step = derivation.step("\tF ≡ A", "B", width)
        assert.are.equal("\t  ≡ B", step)
    end)

    it("measures the head from the start of the line, where a tab's width depends on its column", function()
        -- A tab advances to the next multiple of eight, as in Neovim.
        local function tabbed_width(text)
            local column = 0
            for character in text:gmatch("[^\128-\191][\128-\191]*") do
                column = character == "\t" and column - column % 8 + 8 or column + 1
            end
            return column
        end
        local step = derivation.step("  F\t≡ A ∧ B", "B ∧ A", tabbed_width)
        assert.are.equal("        ≡ B ∧ A", step)
    end)
end)
