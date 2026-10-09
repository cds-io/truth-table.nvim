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

describe("derivation.sides", function()
    it("lists every side in order with its bytes, and the ≡ that opens it", function()
        local line = "F ≡ A ∨ B ≡ B ∨ A"
        local sides = derivation.sides(line)
        assert.are.equal(3, #sides)
        assert.are.same({ text = "F", first = 1, last = 1 }, sides[1])
        assert.are.equal("A ∨ B", line:sub(sides[2].first, sides[2].last))
        assert.are.equal("≡", line:sub(sides[2].separator, sides[2].separator + 2))
        assert.are.equal("B ∨ A", line:sub(sides[3].first, sides[3].last))
        assert.are.equal((line:find("≡", sides[2].separator + 1, true)), sides[3].separator)
    end)

    it("starts a step line at its leading ≡", function()
        local line = "    ≡ S ∨ T    | by commutativity"
        local sides = derivation.sides(line)
        assert.are.equal(1, #sides)
        assert.are.same({ text = "S ∨ T", first = 9, last = 15, separator = 5 }, sides[1])
    end)

    it("leaves blank sides out", function()
        assert.are.same({}, derivation.sides(""))
        assert.are.same({}, derivation.sides("   "))
        assert.are.equal(1, #derivation.sides("F ≡ "))
        assert.are.equal(2, #derivation.sides("F ≡ A ≡ "))
        assert.are.equal(2, #derivation.sides("F ≡   ≡ G"))
    end)

    it("agrees with working_side for a byte in each side", function()
        local line = "F ≡ A ∨ B ≡ B ∨ A"
        for _, side in ipairs(derivation.sides(line)) do
            local chosen = assert(derivation.working_side(line, side.first))
            assert.are.same({ text = side.text, first = side.first, last = side.last }, chosen)
        end
    end)
end)

describe("a justification", function()
    it("ends the sides: no side reaches into it, and a cursor in it selects the last side", function()
        local line = "≡ b ∧ 1        | by complement"
        local side = assert(derivation.working_side(line, 1))
        assert.are.same({ "b ∧ 1", "b ∧ 1" }, { side.text, line:sub(side.first, side.last) })
        assert.are.equal("b ∧ 1", assert(derivation.working_side(line, #line)).text)
        local head = "F ≡ A ∨ B  | by De Morgan"
        assert.are.equal("F", assert(derivation.working_side(head, 1)).text)
        assert.are.equal("A ∨ B", assert(derivation.working_side(head, #head)).text)
    end)

    it("is written `| by` and the law", function()
        assert.are.equal("| by absorption", derivation.justification("absorption"))
    end)
end)

describe("derivation.replace", function()
    it("rewrites one side and keeps the rest of the line byte for byte", function()
        local line = "\t F  ≡  A ∨ B   ≡ C  "
        local side = assert(derivation.working_side(line, (line:find("A", 1, true))))
        assert.are.equal("\t F  ≡  B ∨ A   ≡ C  ", derivation.replace(line, side, { text = "B ∨ A", law = "commutativity" }))
    end)
end)

describe("derivation.replace on a justified line", function()
    it("adds the law to the justification, which then covers both rewrites", function()
        local line = "≡ b ∧ (a ∨ ¬a)    | by distributivity  "
        local side = assert(derivation.working_side(line, 3))
        local replaced = derivation.replace(line, side, { text = "b ∧ 1", law = "complement" })
        assert.are.equal("≡ b ∧ 1    | by distributivity, complement", replaced)
        assert.are.equal("≡ b ∧ 1    | by distributivity  ", derivation.replace(line, side, { text = "b ∧ 1" }))
    end)
end)

describe("derivation.step", function()
    local width = markdown.display_width

    it("justifies a step four columns clear of the wider of the two lines", function()
        local first = derivation.step("(a and b) or (not a and b)", { text = "b ∧ (a ∨ ¬a)", law = "distributivity" }, width)
        assert.are.equal("≡ b ∧ (a ∨ ¬a)                | by distributivity", first)
        local wide = derivation.step("a ∨ b", { text = "¬(¬a ∧ ¬b)", law = "De Morgan" }, width)
        assert.are.equal("≡ ¬(¬a ∧ ¬b)    | by De Morgan", wide)
    end)

    it("puts the bar under the bar above, or further right when the step needs the room", function()
        local above = "≡ b ∧ (a ∨ ¬a)                | by distributivity"
        local step, column = derivation.step(above, { text = "b ∧ 1", law = "complement" }, width)
        assert.are.equal("≡ b ∧ 1                       | by complement", step)
        assert.are.equal(#"≡ ", column)
        local longer = derivation.step("≡ a  | by identity", { text = "a ∨ a ∧ b", law = "absorption" }, width)
        assert.are.equal("≡ a ∨ a ∧ b    | by absorption", longer)
    end)

    it("aligns a justified step under the last separator of a head line", function()
        local step = derivation.step("F ≡ A ∧ B", { text = "B ∧ A", law = "commutativity" }, width)
        assert.are.equal("  ≡ B ∧ A    | by commutativity", step)
    end)

    it("starts at the indentation of a line with no separator", function()
        local step, column = derivation.step("  S ∨ T", { text = "T ∨ S" }, width)
        assert.are.equal("  ≡ T ∨ S", step)
        assert.are.equal(#"  ≡ ", column)
        assert.are.equal("T ∨ S", step:sub(column + 1))
    end)

    it("aligns under the last separator by display column, whatever the byte count", function()
        local head = "S ∨ (A ∧ ¬C) ∨ (G ∧ ¬C) ≡ S ∨ A ∧ ¬C ∨ G ∧ ¬C"
        local step = derivation.step(head, { text = "S ∨ ¬C ∧ (A ∨ G)" }, width)
        assert.are.equal("                        ≡ S ∨ ¬C ∧ (A ∨ G)", step)
        assert.are.equal(width(head:sub(1, (head:find("≡", 1, true)) - 1)), width(step:sub(1, (step:find("≡", 1, true)) - 1)))
    end)

    it("continues a chain from a continuation line", function()
        local step = derivation.step("      ≡ A ∨ B", { text = "B ∨ A" }, width)
        assert.are.equal("      ≡ B ∨ A", step)
    end)

    it("uses the last separator of a line that has several", function()
        local step = derivation.step("F ≡ A ≡ B", { text = "C" }, width)
        assert.are.equal("      ≡ C", step)
    end)

    it("copies leading whitespace verbatim", function()
        local step = derivation.step("\tF ≡ A", { text = "B" }, width)
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
        local step = derivation.step("  F\t≡ A ∧ B", { text = "B ∧ A" }, tabbed_width)
        assert.are.equal("        ≡ B ∧ A", step)
    end)
end)

-- One display column per codepoint, as the pure default.
local function width(s)
    local _, count = s:gsub("[^\128-\191]", "")
    return count
end

describe("derivation.block", function()
    local lines = {
        "prose",
        "",
        "(¬C ∨ (Q ∧ ¬L)) ∧ Q",
        "≡ Q ∧ (¬C ∨ (Q ∧ ¬L))    | by commutativity",
        "≡ (Q ∧ ¬C) ∨ (Q ∧ Q ∧ ¬L)    | by distributivity (distributing)",
        "",
        "≡ an orphan step",
        "F ≡ A ∧ B",
    }

    it("runs from the head a derivation follows from to its last step, from any of its rows", function()
        for row = 3, 5 do
            assert.are.same({ 3, 5 }, { derivation.block(lines, row) }, "from row " .. row)
        end
    end)

    it("is one line for a line that is no step with no step below it", function()
        assert.are.same({ 1, 1 }, { derivation.block(lines, 1) })
        assert.are.same({ 8, 8 }, { derivation.block(lines, 8) })
    end)

    it("takes no blank line as a head, and a step on the first line as its own head", function()
        assert.are.same({ 7, 7 }, { derivation.block(lines, 7) })
        assert.are.same({ 1, 2 }, { derivation.block({ "≡ A", "≡ B", "" }, 2) })
    end)
end)

describe("derivation.aligned", function()
    it("puts every bar four columns past the widest sides in the block", function()
        local block = {
            "(¬C ∨ (Q ∧ ¬L)) ∧ Q",
            "≡ Q ∧ (¬C ∨ (Q ∧ ¬L))    | by commutativity",
            "≡ (Q ∧ ¬C) ∨ (Q ∧ Q ∧ ¬L)    | by distributivity (distributing)",
            "≡ (Q ∧ ¬C) ∨ (Q ∧ ¬L)        | by idempotence",
            "≡ Q ∧ (¬C ∨ ¬L)              | by distributivity (factoring)",
        }
        local aligned = derivation.aligned(block, width)
        assert.are.equal(block[1], aligned[1])
        local column = width("≡ (Q ∧ ¬C) ∨ (Q ∧ Q ∧ ¬L)") + 4
        for i = 2, #aligned do
            local bar = assert(aligned[i]:find("|", 1, true))
            assert.are.equal(column, width(aligned[i]:sub(1, bar - 1)), aligned[i])
            assert.are.equal(block[i]:match("| by .*$"), aligned[i]:match("| by .*$"))
        end
        assert.are.equal("≡ Q ∧ (¬C ∨ (Q ∧ ¬L))        | by commutativity", aligned[2])
    end)

    it("measures a head wider than every step, and leaves lines with no bar as they are", function()
        local block = { "a long head expression here", "≡ b    | by a law", "  not a step, no bar" }
        local aligned = derivation.aligned(block, width)
        assert.are.equal("≡ b" .. string.rep(" ", #"a long head expression here" + 4 - 3) .. "| by a law", aligned[2])
        assert.are.equal(block[1], aligned[1])
        assert.are.equal(block[3], aligned[3])
    end)

    it("pulls a bar back as well as pushing one out", function()
        local block = { "≡ a            | by x", "≡ b ∧ c    | by y" }
        assert.are.same({ "≡ a        | by x", "≡ b ∧ c    | by y" }, derivation.aligned(block, width))
    end)

    it("changes the padding before the bar and nothing else", function()
        local block = { "  F ≡ A ∨ B", "    ≡ B ∨ A  | by commutativity, idempotence" }
        local aligned = derivation.aligned(block, width)
        assert.are.equal("    ≡ B ∨ A    | by commutativity, idempotence", aligned[2])
    end)
end)
