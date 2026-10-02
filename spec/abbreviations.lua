-- Insert-mode abbreviations: defaults from the plugin entry point, then every
-- shape of the setup({ abbreviations = ... }) option. Each setup call must
-- leave exactly its own set registered, whatever the call before it did.
vim.opt.rtp:append(vim.fn.getcwd())
package.preload['which-key'] = function() error('which-key intentionally absent') end
vim.cmd('runtime plugin/truth-table.lua')

local function abbrev(lhs)
    return vim.fn.maparg(lhs, 'i', true)
end
local tt = require('truth-table')
local symbols = require('truth-table.symbols')
local defaults = require('truth-table.abbreviations').defaults

-- The defaults pair each constant's ascii word plus `@` with its unicode symbol.
assert(defaults.trigger == '@')
for _, key in ipairs({ 'NOT', 'AND', 'OR', 'XOR', 'IMPLIES', 'IFF', 'FORALL', 'EXISTS', 'TOP', 'BOTTOM' }) do
    assert(defaults.symbols[symbols[key].ascii] == symbols[key].unicode, key)
end

-- Bare setup from plugin/ registers every default, including the shared
-- rendering for implies and iff.
for word, symbol in pairs(defaults.symbols) do
    assert(abbrev(word .. '@') == symbol, word)
end
assert(abbrev('iff@') == '⇔')
assert(abbrev('implies@') == '→')

-- false registers none, and undoes the earlier call.
tt.setup({ abbreviations = false })
for word in pairs(defaults.symbols) do
    assert(abbrev(word .. '@') == '', word)
end

-- A later bare setup brings the defaults back.
tt.setup()
assert(abbrev('and@') == '∧')

-- symbols merges over the defaults: override one, drop one, add one.
tt.setup({ abbreviations = { symbols = { implies = '⇒', forall = false, top = '⊤' } } })
assert(abbrev('implies@') == '⇒')
assert(abbrev('forall@') == '')
assert(abbrev('top@') == '⊤')
assert(abbrev('and@') == '∧')

-- trigger changes the input side for every word, and the old lhs is gone.
tt.setup({ abbreviations = { trigger = ';' } })
assert(abbrev('and;') == '∧')
assert(abbrev('and@') == '')
assert(abbrev('top;') == '')

-- Reverting to defaults drops the added entry, and survives an abbreviation
-- the user already removed by hand.
tt.setup({ abbreviations = { symbols = { top = '⊤' } } })
vim.cmd('iunabbrev and@')
tt.setup()
assert(abbrev('and@') == '∧')
assert(abbrev('top@') == '')
assert(abbrev('implies@') == '→')

print('Abbreviation setup passed')
