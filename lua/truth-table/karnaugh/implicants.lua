-- Implicants as strings over "0", "1" and "-", one character per input,
-- first input first, where "-" means the variable does not appear in the
-- term (pure Lua 5.1: no bit library). The encoding of a row's inputs as
-- such a pattern, and Quine-McCluskey over them: the prime implicants, and
-- whether a term covers a pattern. The cover search is cover.lua's. Pure.
local M = {}

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

M.pattern_index, M.index_pattern, M.prime_implicants = pattern_index, index_pattern, prime_implicants
M.covers, M.term_key, M.sort_terms = covers, term_key, sort_terms

return M
