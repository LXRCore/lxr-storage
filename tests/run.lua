--[[ ═══════════════════════════════════════════════════════════════════════════
     LXR-STORAGE — Offline tests: prices, states, keys, upgrades, locale parity
     Usage (from the lxr-storage folder):  lua tests/run.lua [--mock out.js en|ka]
     © 2026 iBoss21 / LXRCore — All Rights Reserved
     ═══════════════════════════════════════════════════════════════════════════ ]]

local CORE = os.getenv('LXR_CORE_PATH') or '../lxr-core'
package.path = CORE .. '/?.lua;' .. package.path
local ok = pcall(function() require('tests.lib.fxshim') end)
if not ok then print('lxr-core shim not found at ' .. CORE) os.exit(2) end
local Shim = require('tests.lib.fxshim')
for _, f in ipairs({ 'shared/main.lua', 'shared/locale.lua', 'locales/en.lua', 'config.lua' }) do Shim.load(CORE .. '/' .. f) end
Config = nil Locale = nil
Shim.load('shared/locale.lua') Shim.load('locales/en.lua') Shim.load('locales/ka.lua') Shim.load('config.lua') Shim.load('shared/rules.lua')
local S = LXRStorage

local passed, failed = 0, 0
local function test(name, fn) local okT, err = xpcall(fn, debug.traceback) if okT then passed = passed + 1 print('  ^ ok   ' .. name) else failed = failed + 1 print('  x FAIL ' .. name .. '\n' .. err) end end
local function eq(a, b, msg) if a ~= b then error((msg or 'eq') .. ': expected ' .. tostring(b) .. ' got ' .. tostring(a), 2) end end

print('lxr-storage offline tests')
test('yards and sizes are sane; prices scale by day and yard', function()
    for _, y in ipairs(Config.Yards) do assert(S.Yard(y.id) == y) assert(y.keeper and y.keeper.ped and y.door) for sz in pairs(y.units) do assert(Config.Sizes[sz], y.id .. ' ' .. sz) end end
    local y = Config.Yards[1]
    local p1, d1 = S.Price(y, 'small', 1) eq(p1, Config.Sizes.small.rent) eq(d1, 1)
    local p7 = S.Price(y, 'small', 7) eq(p7, math.floor(Config.Sizes.small.rent * 7 * 100 + 0.5) / 100)
    local _, dcap = S.Price(y, 'small', 999) eq(dcap, Config.Rent.maxDays)
    local sd = S.Price({ priceMult = 2 }, 'small', 1) eq(sd, Config.Sizes.small.rent * 2)
    assert(S.Price(y, 'huge', 1) == nil)
    local order = S.SizeOrder() eq(order[1].id, 'small') eq(order[#order].id, 'large')
end)
test('unit states over time', function()
    local u = { citizenid = 'A', until_ = 1000 }
    eq(S.State({}, 500), 'free') eq(S.State(u, 500), 'paid') eq(S.State(u, 1000), 'paid') eq(S.State(u, 1001), 'locked')
    eq(S.State(u, 1000 + Config.Rent.graceDays * 86400), 'locked') eq(S.State(u, 1001 + Config.Rent.graceDays * 86400), 'cleared')
    eq(S.DaysLeft(u, 1000 - 86400 * 2), 2) eq(S.DaysLeft(u, 5000), 0)
end)
test('keys: tenant, key holders, nobody else', function()
    local u = { citizenid = 'A', keys = { 'B' } }
    assert(S.MayOpen(u, 'A')) assert(S.MayOpen(u, 'B')) assert(not S.MayOpen(u, 'C')) assert(not S.MayOpen({}, 'A'))
    eq(S.StashId({ yard = 'valentine', no = 3 }), 'storage:valentine:3')
end)
test('upgrade cost is the rent difference for the days left, never downward', function()
    local y = Config.Yards[1]
    local diff = Config.Sizes.medium.rent - Config.Sizes.small.rent
    eq(S.UpgradeCost(y, 'small', 'medium', 4), math.floor(diff * 4 * 100 + 0.5) / 100)
    eq(S.UpgradeCost(y, 'small', 'medium', 0.2), math.floor(diff * 1 * 100 + 0.5) / 100, 'at least one day')
    assert(S.UpgradeCost(y, 'large', 'small', 3) == nil)
end)
test('locale parity', function()
    local en, ka = Locale.Bundles.en, Locale.Bundles.ka
    local missing = {}
    for k in pairs(en) do if ka[k] == nil then missing[#missing + 1] = k end end
    eq(#missing, 0, 'ka missing: ' .. table.concat(missing, ', '))
end)
print(('%d passed, %d failed'):format(passed, failed))
if arg and arg[1] == '--mock' and arg[2] then
    Config.Lang = arg[3] or 'en'
    local y = Config.Yards[1]
    local units, no = {}, 0
    for _, sz in ipairs(S.SizeOrder()) do for i = 1, y.units[sz.id] do no = no + 1 local st = (no == 3 or no == 9 or no == 14) and 'taken' or (no == 5) and 'paid' or (no == 16) and 'key' or 'free' units[#units + 1] = { no = no, size = sz.id, state = st == 'taken' and 'paid' or st == 'key' and 'paid' or st, mine = st == 'paid', key = st == 'key', daysLeft = st == 'paid' and 11.4 or nil, code = st == 'paid' and true or nil, keys = st == 'paid' and { 'LXR9F8E7D' } or nil, tenant = (st == 'paid') and 'Sadie Adler' or (st == 'key') and 'Nino Kvaratskhelia' or nil } end end
    local sizes = {}
    for _, sz in ipairs(S.SizeOrder()) do sizes[#sizes + 1] = { id = sz.id, slots = sz.slots, weight = sz.weight, rent = S.Price(y, sz.id, 1) } end
    local f = assert(io.open(arg[2], 'w'))
    f:write('window.__LXR_MOCK__ = ' .. json.encode({ action = 'open', payload = { yard = { id = y.id, label = y.label }, units = units, sizes = sizes, cash = 9.75, maxDays = Config.Rent.maxDays, graceDays = Config.Rent.graceDays, maxKeys = Config.Rent.keys }, lang = Config.Lang, locale = Lang.bundle(), brand = { name = 'The Land of Wolves', theme = 'night' } }) .. ';\n')
    f:close()
    print('mock written to ' .. arg[2])
end
os.exit(failed == 0 and 0 or 1)
