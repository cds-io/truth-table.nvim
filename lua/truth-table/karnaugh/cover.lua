-- The minimal cover of a column's minterms by its prime implicants: the
-- essential primes first, then an exact branch-and-bound search over what
-- they leave, within a budget past which the greedy answer stands. Over
-- the implicant strings of implicants.lua. Pure.
local fp = require("cds.fp")
local implicants = require("truth-table.karnaugh.implicants")
local M = {}

local covers, term_key, sort_terms = implicants.covers, implicants.term_key, implicants.sort_terms

-- A loop where the rest of karnaugh/ would use fp.filter: the cover search
-- calls this for every candidate at every node, and the closure a filter
-- needs per call cost about 6% of the Karnaugh spec's run time under Lua 5.1.
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
    return fp.reduce(terms, 0, function(count, term)
        local _, literals = term:gsub("[01]", "")
        return count + literals
    end)
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
    local chosen = fp.set(cover)
    local uncovered = fp.filter(minterms, function(pattern)
        return not covered[pattern]
    end)
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

M.minimal_cover = minimal_cover

return M
