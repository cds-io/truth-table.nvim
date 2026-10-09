-- The operators of the predicate language, in one table: for each, its
-- keyword, its rendered symbol, the further spellings the tokenizer accepts,
-- its binding power and its Boolean meaning. The parser and evaluator
-- (truth-table.predicate) and the renderer (truth-table.trees) all read this
-- centralized operator metadata. The keyword and rendered symbol
-- come from truth-table.symbols so the abbreviations stay in step; every
-- alias list includes the rendered symbol so headings round-trip.
local SYMBOLS = require("truth-table.symbols")
local M = {}

-- Ordered from tightest to loosest. Every binary operator associates left.
-- stylua: ignore start
-- Packed rows: each operator's names and aliases on a line, its apply below.
M.OPERATORS = {
    { name = SYMBOLS.NOT.ascii, symbol = SYMBOLS.NOT.unicode, aliases = { SYMBOLS.NOT.unicode, "!" }, unary = true,
        apply = function(a) return a == 0 end },
    { name = SYMBOLS.AND.ascii, symbol = SYMBOLS.AND.unicode, aliases = { SYMBOLS.AND.unicode },
        apply = function(a, b) return a == 1 and b == 1 end },
    { name = SYMBOLS.OR.ascii, symbol = SYMBOLS.OR.unicode, aliases = { SYMBOLS.OR.unicode },
        apply = function(a, b) return a == 1 or b == 1 end },
    { name = SYMBOLS.XOR.ascii, symbol = SYMBOLS.XOR.unicode, aliases = { SYMBOLS.XOR.unicode },
        apply = function(a, b) return a ~= b end },
    { name = SYMBOLS.IMPLIES.ascii, symbol = SYMBOLS.IMPLIES.unicode,
        aliases = { SYMBOLS.IMPLIES.unicode, "⇒", "->", "=>" },
        apply = function(a, b) return a == 0 or b == 1 end },
    { name = SYMBOLS.IFF.ascii, symbol = SYMBOLS.IFF.unicode,
        aliases = { SYMBOLS.IFF.unicode, "=", "↔", "<->", "<=>" },
        apply = function(a, b) return a == b end },
}
-- stylua: ignore end

-- By operator name: KEYWORDS, the words that are operators; BINARY, the
-- two-operand ones; BY_NAME, the record above; SYMBOLS, the rendered symbol,
-- under "!" as well for ¬. SYMBOL_OPS is every spelling the tokenizer
-- accepts with the name it reads as, longest first so overlapping spellings
-- need no ordering of their own.
M.KEYWORDS, M.BINARY, M.BY_NAME, M.SYMBOLS, M.SYMBOL_OPS = {}, {}, {}, {}, {}
for index, operator in ipairs(M.OPERATORS) do
    M.KEYWORDS[operator.name] = true
    M.BY_NAME[operator.name] = operator
    operator.precedence = #M.OPERATORS - index + 1
    M.SYMBOLS[operator.name] = operator.symbol
    if not operator.unary then
        M.BINARY[operator.name] = true
    end
    for _, alias in ipairs(operator.aliases) do
        -- "!" keeps its own spelling in the token stream.
        M.SYMBOL_OPS[#M.SYMBOL_OPS + 1] = { alias, alias == "!" and "!" or operator.name }
    end
end
M.SYMBOLS["!"] = M.SYMBOLS["not"]
table.sort(M.SYMBOL_OPS, function(a, b)
    return #a[1] > #b[1]
end)

-- The constants: the digits, with ⊤ and ⊥ as further spellings of 1 and 0.
-- The words `true` and `false` are read as ⊤ and ⊥, the way `and` is read as
-- ∧, which reserves them: neither can name a column.
M.CONSTANTS = { ["0"] = 0, ["1"] = 1, [SYMBOLS.TOP.unicode] = 1, [SYMBOLS.BOTTOM.unicode] = 0 }
M.CONSTANT_WORDS = {
    [SYMBOLS.TOP.ascii] = SYMBOLS.TOP.unicode,
    [SYMBOLS.BOTTOM.ascii] = SYMBOLS.BOTTOM.unicode,
}

return M
