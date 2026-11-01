-- Karnaugh maps and minimal sum-of-products formulas for one table column.
-- Pure Lua 5.1 (busted runs PUC Lua, Neovim runs LuaJIT): no bit library, so
-- implicants are strings over "0", "1" and "-" with one character per input,
-- first input first. A "-" means the variable does not appear in the term.
-- The analysis is here: the input columns, the minterms and don't-cares,
-- and the cover as a formula. The implicant strings and Quine-McCluskey
-- are implicants.lua, the cover search cover.lua, and the drawn map map.lua,
-- whose `render` this also answers to.
local fp = require("cds.fp")
local list = require("truth-table.list")
local predicate = require("truth-table.predicate")
local trees = require("truth-table.trees")
local implicants = require("truth-table.karnaugh.implicants")
local minimal_cover = require("truth-table.karnaugh.cover").minimal_cover
local map = require("truth-table.karnaugh.map")
local M = {}

local pattern_index, index_pattern = implicants.pattern_index, implicants.index_pattern
local prime_implicants, sort_terms = implicants.prime_implicants, implicants.sort_terms
M.render = map.render

-- The inputs are the shortest prefix of the columns before the target that
-- distinguishes every row. The data decides, so a computed column after the
-- variables is never an input, and a table with dropped rows still works
-- (missing patterns become don't-cares).
local function input_count(tbl, column)
    if column == 1 then
        return nil, "No input columns before " .. tbl.headers[1]
    end
    local collision
    for width = 1, column - 1 do
        local seen = {}
        collision = nil
        for index, row in ipairs(tbl.rows) do
            local key = table.concat(row, "", 1, width)
            if seen[key] then
                collision = { seen[key], index }
                break
            end
            seen[key] = index
        end
        if not collision then
            return width
        end
    end
    local first, second = tbl.rows[collision[1]], tbl.rows[collision[2]]
    local heading = tbl.headers[column]
    if first[column] == second[column] then
        return nil, string.format("Rows %d and %d repeat the same inputs", collision[1], collision[2])
    end
    return nil,
        string.format("Rows %d and %d agree on every input but disagree on %s", collision[1], collision[2], heading)
end

-- Whether each input heading is a bare identifier, which a term then names
-- as the variable; any other heading refers to its stored column through
-- :hN.
local function variables(inputs)
    return fp.map(inputs, function(heading)
        local parsed = predicate.parse_expression(heading)
        return parsed ~= nil and parsed.type == "var" and parsed.name == heading
    end)
end

local function term_ast(term, inputs, variable)
    local literals = {}
    for i = 1, #term do
        local ch = term:sub(i, i)
        local input = variable[i] and trees.var(inputs[i]) or trees.reference(i)
        if ch == "1" then
            literals[#literals + 1] = input
        elseif ch == "0" then
            literals[#literals + 1] = trees.negation(input)
        end
    end
    if #literals == 0 then
        return trees.literal(1)
    end
    return trees.fold("and", literals)
end

local function cover_ast(cover, inputs)
    if #cover == 0 then
        return trees.literal(0)
    end
    local variable = variables(inputs)
    return trees.fold(
        "or",
        fp.map(cover, function(term)
            return term_ast(term, inputs, variable)
        end)
    )
end

-- Analyse column `column` of a table model. Returns:
--   inputs      names of the input columns, in table order
--   target      the column's heading
--   values      pattern string -> 0/1, for every row
--   minterms    indices (first input is the high bit) where the column is 1
--   dont_cares  indices of input patterns no row supplies
--   primes      prime implicants, sorted
--   cover       the chosen minimal cover, sorted
--   ast         the cover as a predicate AST (sum of products)
--   formula     the AST rendered in the predicate language
--   encoding    the table's "bits" or "tf"
function M.derive(tbl, column)
    if type(column) ~= "number" or column ~= math.floor(column) or column < 1 or column > #tbl.headers then
        return nil, "Invalid column index: " .. tostring(column)
    end
    local width, width_err = input_count(tbl, column)
    if not width then
        return nil, width_err
    end
    local inputs = list.slice(tbl.headers, 1, width)
    local values, minterms, terms = {}, {}, {}
    for _, row in ipairs(tbl.rows) do
        local pattern = table.concat(row, "", 1, width)
        values[pattern] = row[column]
        if row[column] == 1 then
            minterms[#minterms + 1] = pattern_index(pattern)
            terms[#terms + 1] = pattern
        end
    end
    local dont_cares = {}
    for index = 0, 2 ^ width - 1 do
        local pattern = index_pattern(index, width)
        if values[pattern] == nil then
            dont_cares[#dont_cares + 1] = index
            terms[#terms + 1] = pattern
        end
    end
    table.sort(minterms)
    local minterm_patterns = fp.map(minterms, function(index)
        return index_pattern(index, width)
    end)
    local primes = sort_terms(prime_implicants(terms))
    local cover = minimal_cover(primes, minterm_patterns)
    local ast = cover_ast(cover, inputs)
    return {
        inputs = inputs,
        target = tbl.headers[column],
        values = values,
        minterms = minterms,
        dont_cares = dont_cares,
        primes = primes,
        cover = cover,
        ast = ast,
        formula = trees.heading(ast),
        encoding = tbl.encoding,
    }
end

return M
