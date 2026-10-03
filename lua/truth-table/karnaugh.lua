-- Karnaugh maps and minimal sum-of-products formulas for one table column.
-- Pure Lua 5.1 (busted runs PUC Lua, Neovim runs LuaJIT): no bit library, so
-- implicants are strings over "0", "1" and "-" with one character per input,
-- first input first. A "-" means the variable does not appear in the term.
local result = require("truth-table.result")
local model = require("truth-table.table_model")
local markdown = require("truth-table.markdown")
local predicate = require("truth-table.predicate")
local SYMBOLS = require("truth-table.symbols")

local M = {}

-- Reflexive Gray code: each neighbour differs in one bit, including wrapping.
local GRAY = { { "0", "1" }, { "00", "01", "11", "10" } }

-- The inputs are the shortest prefix of the columns before the target that
-- distinguishes every row. The data decides, so a computed column after the
-- variables is never an input, and a table with dropped rows still works
-- (missing patterns become don't-cares).
local function input_count(valid, column)
    if column == 1 then
        return nil, "No input columns before " .. valid.headers[1]
    end
    local collision
    for width = 1, column - 1 do
        local seen = {}
        collision = nil
        for index, row in ipairs(valid.rows) do
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
    local first, second = valid.rows[collision[1]], valid.rows[collision[2]]
    local heading = valid.headers[column]
    if first[column] == second[column] then
        return nil, string.format("Rows %d and %d repeat the same inputs", collision[1], collision[2])
    end
    return nil, string.format("Rows %d and %d agree on every input but disagree on %s",
        collision[1], collision[2], heading)
end

local function pattern_index(pattern)
    local value = 0
    for i = 1, #pattern do
        value = value * 2 + (pattern:sub(i, i) == "1" and 1 or 0)
    end
    return value
end

local function index_pattern(index, width)
    local chars = {}
    for position = width, 1, -1 do
        chars[position] = tostring(index % 2)
        index = math.floor(index / 2)
    end
    return table.concat(chars)
end

-- Position of the single differing literal, or nil. Dashes must line up:
-- terms with different free variables never combine.
local function differs_in_one(a, b)
    local position
    for i = 1, #a do
        local ca, cb = a:sub(i, i), b:sub(i, i)
        if ca ~= cb then
            if ca == "-" or cb == "-" or position then
                return nil
            end
            position = i
        end
    end
    return position
end

local function count_ones(term)
    local _, ones = term:gsub("1", "")
    return ones
end

-- Quine-McCluskey: combine terms that differ in one literal until nothing
-- combines; whatever never combined is a prime implicant. Candidates are
-- bucketed by their dash positions and their count of ones, since only a
-- bucket and its ones+1 neighbour can ever merge.
local function prime_implicants(terms)
    local primes, is_prime = {}, {}
    local current = terms
    while #current > 0 do
        local buckets, keys = {}, {}
        for _, term in ipairs(current) do
            local key = term:gsub("[01]", ".") .. count_ones(term)
            if not buckets[key] then
                buckets[key] = {}
                keys[#keys + 1] = key
            end
            local bucket = buckets[key]
            bucket[#bucket + 1] = term
        end
        local combined, merged, seen = {}, {}, {}
        for _, key in ipairs(keys) do
            local shape, ones = key:match("^(.-)(%d+)$")
            local neighbour = buckets[shape .. (tonumber(ones) + 1)]
            if neighbour then
                for _, a in ipairs(buckets[key]) do
                    for _, b in ipairs(neighbour) do
                        local position = differs_in_one(a, b)
                        if position then
                            combined[a], combined[b] = true, true
                            local term = a:sub(1, position - 1) .. "-" .. a:sub(position + 1)
                            if not seen[term] then
                                seen[term] = true
                                merged[#merged + 1] = term
                            end
                        end
                    end
                end
            end
        end
        for _, term in ipairs(current) do
            if not combined[term] and not is_prime[term] then
                is_prime[term] = true
                primes[#primes + 1] = term
            end
        end
        current = merged
    end
    return primes
end

local function covers(term, pattern)
    for i = 1, #term do
        local ch = term:sub(i, i)
        if ch ~= "-" and ch ~= pattern:sub(i, i) then
            return false
        end
    end
    return true
end

-- Sort literals before free variables, so `A ∧ ¬B` precedes `A ∧ C`, and the
-- tie-break between equal covers is the one a reader would guess.
local function term_key(term)
    return (term:gsub("%-", "2"))
end

local function sort_terms(terms)
    table.sort(terms, function(a, b)
        return term_key(a) < term_key(b)
    end)
    return terms
end

local function without_covered(term, patterns)
    local rest = {}
    for _, pattern in ipairs(patterns) do
        if not covers(term, pattern) then
            rest[#rest + 1] = pattern
        end
    end
    return rest
end

-- Repeatedly take the candidate covering the most of what is left (first in
-- candidate order on a tie). Not always minimal, but linear, and every
-- uncovered minterm has some candidate, so it always finishes.
local function greedy_cover(candidates, uncovered)
    local cover, remaining = {}, uncovered
    while #remaining > 0 do
        local best_index, best_count = nil, 0
        for i, term in ipairs(candidates) do
            local count = #remaining - #without_covered(term, remaining)
            if count > best_count then
                best_index, best_count = i, count
            end
        end
        cover[#cover + 1] = candidates[best_index]
        remaining = without_covered(candidates[best_index], remaining)
    end
    return cover
end

-- Minimum set cover is NP-hard; a random function of ten variables leaves
-- hundreds of non-essential primes, and an unbounded search runs for minutes.
-- The budget is in search nodes, so small maps (the ones anyone draws) are
-- always solved exactly and large ones degrade to the greedy answer.
local SEARCH_BUDGET = 5000

local function literal_count(terms)
    local count = 0
    for _, term in ipairs(terms) do
        local _, literals = term:gsub("[01]", "")
        count = count + literals
    end
    return count
end

local function better_cover(candidate, best)
    if not best or #candidate ~= #best then
        return not best or #candidate < #best
    end
    local candidate_literals, best_literals = literal_count(candidate), literal_count(best)
    if candidate_literals ~= best_literals then
        return candidate_literals < best_literals
    end
    for i, term in ipairs(candidate) do
        if term ~= best[i] then
            return term_key(term) < term_key(best[i])
        end
    end
    return false
end

-- Smallest subset of `candidates` covering every pattern in `uncovered`,
-- minimizing terms, then literals, then lexical order. Branch and bound prunes any branch
-- that cannot beat the best cover found so far.
local function exact_cover(candidates, uncovered)
    local best, nodes, exhausted
    local chosen = {}
    local function search(start, remaining)
        nodes = (nodes or 0) + 1
        if nodes > SEARCH_BUDGET then
            exhausted = true
            return
        end
        if #remaining == 0 then
            if better_cover(chosen, best) then
                best = { unpack(chosen) }
            end
            return
        end
        if best and #chosen + 1 > #best then
            return
        end
        for i = start, #candidates do
            if exhausted then
                return
            end
            local rest = without_covered(candidates[i], remaining)
            if #rest < #remaining then
                chosen[#chosen + 1] = candidates[i]
                search(i + 1, rest)
                chosen[#chosen] = nil
            end
        end
    end
    search(1, uncovered)
    if exhausted then
        local greedy = sort_terms(greedy_cover(candidates, uncovered))
        if better_cover(greedy, best) then
            return greedy
        end
    end
    return best or {}
end

local function minimal_cover(primes, minterms)
    local cover, covered = {}, {}
    -- Essential primes: the only cover of some minterm. Taking them first
    -- shrinks the exact search to the genuinely ambiguous cells.
    local changed = true
    while changed do
        changed = false
        for _, pattern in ipairs(minterms) do
            if not covered[pattern] then
                local only
                for _, prime in ipairs(primes) do
                    if covers(prime, pattern) then
                        if only then
                            only = nil
                            break
                        end
                        only = prime
                    end
                end
                if only then
                    cover[#cover + 1] = only
                    for _, other in ipairs(minterms) do
                        if covers(only, other) then
                            covered[other] = true
                        end
                    end
                    changed = true
                end
            end
        end
    end
    local uncovered, chosen = {}, {}
    for _, prime in ipairs(cover) do
        chosen[prime] = true
    end
    for _, pattern in ipairs(minterms) do
        if not covered[pattern] then
            uncovered[#uncovered + 1] = pattern
        end
    end
    if #uncovered > 0 then
        local candidates = {}
        for _, prime in ipairs(primes) do
            if not chosen[prime] then
                for _, pattern in ipairs(uncovered) do
                    if covers(prime, pattern) then
                        candidates[#candidates + 1] = prime
                        break
                    end
                end
            end
        end
        for _, prime in ipairs(exact_cover(candidates, uncovered)) do
            cover[#cover + 1] = prime
        end
    end
    return sort_terms(cover)
end

local function fold(nodes, operator)
    local node = nodes[1]
    for i = 2, #nodes do
        node = { type = operator, left = node, right = nodes[i] }
    end
    return node
end

local function term_ast(term, inputs)
    local literals = {}
    for i = 1, #term do
        local ch = term:sub(i, i)
        -- Only a bare identifier can safely be rendered as a variable.
        -- Other headings refer to stored column values through :hN.
        local parsed = predicate.parse_expression(inputs[i])
        local input = parsed and parsed.type == "var" and parsed.name == inputs[i]
            and { type = "var", name = inputs[i] } or { type = "reference", index = i }
        if ch == "1" then
            literals[#literals + 1] = input
        elseif ch == "0" then
            literals[#literals + 1] = { type = "not", operand = input }
        end
    end
    if #literals == 0 then
        return { type = "literal", value = 1 }
    end
    return fold(literals, "and")
end

local function cover_ast(cover, inputs)
    if #cover == 0 then
        return { type = "literal", value = 0 }
    end
    local terms = {}
    for i, term in ipairs(cover) do
        terms[i] = term_ast(term, inputs)
    end
    return fold(terms, "or")
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
    local valid, err = model.normalize(tbl)
    if not valid then
        return nil, err
    end
    if type(column) ~= "number" or column ~= math.floor(column) or column < 1 or column > #valid.headers then
        return nil, "Invalid column index: " .. tostring(column)
    end
    local width, width_err = input_count(valid, column)
    if not width then
        return nil, width_err
    end
    local inputs = {}
    for i = 1, width do
        inputs[i] = valid.headers[i]
    end
    local values, minterms, terms = {}, {}, {}
    for _, row in ipairs(valid.rows) do
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
    local minterm_patterns = result.traverse(minterms, function(index)
        return index_pattern(index, width)
    end)
    local primes = sort_terms(prime_implicants(terms))
    local cover = minimal_cover(primes, minterm_patterns)
    local ast = cover_ast(cover, inputs)
    return {
        inputs = inputs,
        target = valid.headers[column],
        values = values,
        minterms = minterms,
        dont_cares = dont_cares,
        primes = primes,
        cover = cover,
        ast = ast,
        formula = predicate.ast_to_heading(ast),
        encoding = valid.encoding,
    }
end

local function axis_label(names)
    for _, name in ipairs(names) do
        if #name > 1 then
            return table.concat(names, " ")
        end
    end
    return table.concat(names)
end

-- Textbook layout: the last two inputs run across the columns (one input for
-- a two-variable map), the rest down the rows, both in Gray order. An extra
-- heading row and leading column carry the axis labels. Maps are drawn for
-- two to four inputs; a larger map would need stacked panels.
function M.map_cells(analysis)
    local width = #analysis.inputs
    if width < 2 or width > 4 then
        return nil
    end
    local column_count = width == 2 and 1 or 2
    local row_count = width - column_count
    local row_names, column_names = {}, {}
    for i = 1, row_count do
        row_names[i] = analysis.inputs[i]
    end
    for i = 1, column_count do
        column_names[i] = analysis.inputs[row_count + i]
    end
    local row_codes, column_codes = GRAY[row_count], GRAY[column_count]
    local symbols = analysis.encoding == "tf" and { [0] = "F", [1] = "T" } or { [0] = "0", [1] = "1" }

    local headers = { "", "" }
    for i = 1, #column_codes do
        headers[2 + i] = ""
    end
    headers[2 + math.ceil(#column_codes / 2)] = axis_label(column_names)

    local rows = { { "", "" } }
    for i, code in ipairs(column_codes) do
        rows[1][2 + i] = code
    end
    for r, row_code in ipairs(row_codes) do
        local cells = { r == 1 and axis_label(row_names) or "", row_code }
        for _, column_code in ipairs(column_codes) do
            local value = analysis.values[row_code .. column_code]
            cells[#cells + 1] = value == nil and "X" or symbols[value]
        end
        rows[#rows + 1] = cells
    end
    return headers, rows
end

-- Lines to insert below the table: the map (when drawable) and the formula.
function M.render(analysis, display_width)
    local formula = analysis.target .. " " .. SYMBOLS.EQUIV.unicode .. " " .. analysis.formula
    local headers, rows = M.map_cells(analysis)
    if not headers then
        return { formula }
    end
    local lines = { "Karnaugh map for " .. analysis.target .. ":", "" }
    for _, line in ipairs(markdown.format_cells(headers, rows, display_width)) do
        lines[#lines + 1] = line
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = formula
    return lines
end

return M
