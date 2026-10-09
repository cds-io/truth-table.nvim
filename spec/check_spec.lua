-- The derivation check: each side judged against the side before it over
-- every assignment of their variables, and the first step that fails.
local check = require("truth-table.check")

describe("check.check", function()
    it("holds when every step is an equivalence, and counts the steps", function()
        local verdict = assert(check.check({
            "(a ∧ b) ∨ (¬a ∧ b)",
            "≡ b ∧ (a ∨ ¬a)    | by distributivity (factoring)",
            "≡ b ∧ 1           | by complement",
            "≡ b               | by identity",
        }))
        assert.are.same({
            ok = true,
            steps = 3,
            texts = { "(a ∧ b) ∨ (¬a ∧ b)", "b ∧ (a ∨ ¬a)", "b ∧ 1", "b" },
            variables = { "a", "b" },
        }, verdict)
    end)

    it("reads several sides on one line as several steps", function()
        assert.are.same(
            {
                ok = true,
                steps = 3,
                texts = { "a → b", "¬a ∨ b", "b ∨ ¬a", "¬(¬b ∧ a)" },
                variables = { "a", "b" },
            },
            assert(check.check({
                "a → b ≡ ¬a ∨ b ≡ b ∨ ¬a",
                "≡ ¬(¬b ∧ a)",
            }))
        )
    end)

    it("is zero steps for a block of one side, and for a line with no side", function()
        assert.are.same({ ok = true, steps = 0 }, assert(check.check({ "a ∧ b" })))
        assert.are.same({ ok = true, steps = 0 }, assert(check.check({ "| A | B |" })))
        assert.are.same({ ok = true, steps = 0 }, assert(check.check({})))
    end)

    it("is zero steps for a line that is no expression at all, without parsing it", function()
        assert.are.same({ ok = true, steps = 0 }, assert(check.check({ "This is a proof of the claim." })))
        assert.are.same({ ok = true, steps = 0 }, assert(check.check({ "## Proof" })))
    end)

    it("orders the assignment as the chain first mentions the variables", function()
        local verdict = assert(check.check({ "a ∧ b", "≡ b ∧ a", "≡ b" }))
        assert.are.equal(2, verdict.step)
        assert.are.same({ { name = "a", value = 0 }, { name = "b", value = 1 } }, verdict.assignment)
    end)

    it("lists every side's text in canonical form, in chain order, on either verdict", function()
        local holds = assert(check.check({ "a and b", "≡ b ∧ a", "≡ b and a" }))
        assert.are.same({ "a ∧ b", "b ∧ a", "b ∧ a" }, holds.texts)
        local fails = assert(check.check({ "a ∨ b", "≡ a" }))
        assert.are.same({ "a ∨ b", "a" }, fails.texts)
        assert.are.same({ "a", "b" }, fails.variables)
        assert.are.same({ "a", "b" }, holds.variables)
    end)

    it("reports the first failing step with the assignment that breaks it", function()
        local verdict = assert(check.check({
            "a ∨ b",
            "≡ a ∨ (b ∧ a)   | by absorption",
            "≡ a             | by absorption",
        }))
        assert.is_false(verdict.ok)
        assert.are.equal(1, verdict.step)
        assert.are.equal(2, verdict.row)
        assert.are.same({ 5, 19 }, verdict.side)
        assert.are.equal(1, verdict.separator)
        assert.are.same({ { name = "a", value = 0 }, { name = "b", value = 1 } }, verdict.assignment)
        assert.are.equal(1, verdict.premise)
        assert.are.equal(0, verdict.conclusion)
    end)

    it("stops at the first failing step whether or not later steps hold", function()
        local wrong_then_right = assert(check.check({ "a ∧ b", "≡ a", "≡ a ∨ (a ∧ b)" }))
        assert.are.equal(1, wrong_then_right.step)
        local wrong_then_wrong = assert(check.check({ "a ∧ b", "≡ a", "≡ b" }))
        assert.are.equal(1, wrong_then_wrong.step)
        local right_then_wrong = assert(check.check({ "a ∧ b", "≡ b ∧ a", "≡ b" }))
        assert.are.equal(2, right_then_wrong.step)
        assert.are.equal(3, right_then_wrong.row)
    end)

    it("places a conclusion in the middle of a line by its own ≡", function()
        local line = "F ≡ F ∧ F ≡ ¬F"
        local verdict = assert(check.check({ line }))
        assert.are.equal(2, verdict.step)
        assert.are.equal(1, verdict.row)
        assert.are.equal((line:find("≡", 4, true)), verdict.separator)
        assert.are.equal("¬F", line:sub(verdict.side[1], verdict.side[2]))
    end)

    it("judges a dropped variable over every value it had", function()
        assert.is_true(assert(check.check({ "b ∧ (a ∨ ¬a)", "≡ b" })).ok)
        local verdict = assert(check.check({ "a ∨ b", "≡ a" }))
        assert.is_false(verdict.ok)
        assert.are.same({ { name = "a", value = 0 }, { name = "b", value = 1 } }, verdict.assignment)
    end)

    it("judges a step with no variables over its one row", function()
        assert.is_true(assert(check.check({ "⊤", "≡ 1" })).ok)
        local verdict = assert(check.check({ "1", "≡ 0" }))
        assert.is_false(verdict.ok)
        assert.are.same({}, verdict.assignment)
        assert.are.equal("step 1: 1 ≢ 0", check.message(verdict))
    end)

    it("leaves a trailing blank side out", function()
        assert.are.same(
            { ok = true, steps = 1, texts = { "a ∧ b", "b ∧ a" }, variables = { "a", "b" } },
            assert(check.check({ "a ∧ b ≡ b ∧ a ≡ " }))
        )
    end)

    it("ignores the justification", function()
        local bare = assert(check.check({ "a ∨ b", "≡ a" }))
        local justified = assert(check.check({ "a ∨ b", "≡ a    | by a law that does not exist" }))
        assert.are.same(bare.assignment, justified.assignment)
        assert.are.equal(bare.step, justified.step)
    end)

    it("refuses a side that does not parse, naming it", function()
        local verdict, err = check.check({ "a ∧ b", "≡ a ∧", "≡ a" })
        assert.is_nil(verdict)
        assert.is_truthy(err:find('Parse error in "a ∧"', 1, true))
    end)

    it("refuses a column reference, naming it", function()
        local verdict, err = check.check({ "a ∧ :h2", "≡ :h2 ∧ a" })
        assert.is_nil(verdict)
        assert.are.equal(":h2 has no meaning outside a table", err)
    end)

    it("refuses a step over more than ten variables", function()
        local many = "a ∨ b ∨ c ∨ d ∨ e ∨ f ∨ g ∨ h ∨ i ∨ j ∨ k"
        local verdict, err = check.check({ many, "≡ " .. many })
        assert.is_nil(verdict)
        assert.are.equal("Too many variables (max 10)", err)
    end)
end)

describe("check.message", function()
    it("names the step, the assignment in order of appearance, and the two values", function()
        local verdict = assert(check.check({ "b ∨ a", "≡ b" }))
        assert.are.equal("step 1: b=0, a=1 gives 1 ≢ 0", check.message(verdict))
    end)
end)
