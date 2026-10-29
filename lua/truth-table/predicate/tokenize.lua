-- The tokenizer of the predicate language: source in, tokens out, each with
-- the bytes it was read from. The first stage of the pipeline in init.lua,
-- on its own so the lexical rules (what is a reference, an operator symbol,
-- a keyword, a constant) read apart from the grammar. Pure.
local operators = require("truth-table.operators")
local SYMBOL_OPS, KEYWORDS = operators.SYMBOL_OPS, operators.KEYWORDS
local CONSTANTS, CONSTANT_WORDS = operators.CONSTANTS, operators.CONSTANT_WORDS
local M = {}

local function symbol_op_at(input, pos)
    for _, entry in ipairs(SYMBOL_OPS) do
        local symbol = entry[1]
        if input:sub(pos, pos + #symbol - 1) == symbol then
            return entry[2], #symbol
        end
    end
end

-- The tokens of `input`, each { type, value, span }, the span the one-based,
-- inclusive bytes it was read from; or nil and the reason at the first
-- character that is no token.
function M.tokenize(input)
    local tokens = {}
    local pos = 1
    local len = #input

    while pos <= len do
        local ws = input:match("^%s+", pos)
        if ws then
            pos = pos + #ws
        end
        if pos > len then
            break
        end

        local token_start = pos
        local ch = input:sub(pos, pos)
        local symbol_op, symbol_len = symbol_op_at(input, pos)

        if ch == ":" then
            local reference = input:match("^:h%d+", pos)
            if not reference or input:sub(pos + #reference, pos + #reference):match("[%w_:]") then
                return nil, "Invalid column reference at byte " .. pos .. "; expected :hN"
            end
            local index = tonumber(reference:sub(3))
            if index < 1 or index == math.huge then
                return nil, "Column reference must have a positive index at byte " .. pos
            end
            tokens[#tokens + 1] = { type = "reference", value = index }
            pos = pos + #reference
        elseif symbol_op then
            tokens[#tokens + 1] = { type = "op", value = symbol_op }
            pos = pos + symbol_len
        elseif ch == "(" or ch == ")" then
            tokens[#tokens + 1] = { type = "paren", value = ch }
            pos = pos + 1
        elseif ch:match("[A-Za-z_]") then
            local ident = input:match("^[A-Za-z_][A-Za-z0-9_]*", pos)
            if KEYWORDS[ident] then
                tokens[#tokens + 1] = { type = "op", value = ident }
            elseif CONSTANT_WORDS[ident] then
                tokens[#tokens + 1] = { type = "literal", value = CONSTANT_WORDS[ident] }
            else
                tokens[#tokens + 1] = { type = "ident", value = ident }
            end
            pos = pos + #ident
        else
            local character = input:match("^[^\128-\191][\128-\191]*", pos) or ch
            if not CONSTANTS[character] then
                return nil, "Unexpected character: " .. character .. " at byte " .. pos
            end
            tokens[#tokens + 1] = { type = "literal", value = character }
            pos = pos + #character
        end
        tokens[#tokens].span = { start_byte = token_start, end_byte = pos - 1 }
    end
    return tokens
end

return M
