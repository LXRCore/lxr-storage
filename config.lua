--[[
    ██╗     ██╗  ██╗██████╗       ███████╗████████╗ ██████╗ ██████╗  █████╗  ██████╗ ███████╗
    ██║     ╚██╗██╔╝██╔══██╗      ██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗██╔══██╗██╔════╝ ██╔════╝
    ██║      ╚███╔╝ ██████╔╝█████╗███████╗   ██║   ██║   ██║██████╔╝███████║██║  ███╗█████╗
    ██║      ██╔██╗ ██╔══██╗╚════╝╚════██║   ██║   ██║   ██║██╔══██╗██╔══██║██║   ██║██╔══╝
    ███████╗██╔╝ ██╗██║  ██║      ███████║   ██║   ╚██████╔╝██║  ██║██║  ██║╚██████╔╝███████╗
    ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝      ╚══════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝

    LXR Core - Storage

    Rented lock-ups. A warehouse keeper at each yard rents numbered units by
    the day: small, medium, large. Rent runs out, the unit is padlocked and
    the keeper keeps what is inside until it is paid; a month unpaid and
    the unit is cleared. A tenant can hand a key to another citizen, set a
    combination, or move to a bigger unit. Every unit is an lxr-inventory
    stash; the keeper's book is this resource.

    Brand:       LXRCore — Lux Empire eXperience RedM Core
    Product:     wolves.land / The Land of Wolves
    Developer:   iBoss21 / LXRCore
    Website:     https://www.lxrcore.com
    Discord:     https://discord.gg/ZHMKVYyhBa (development)
    GitHub:      https://github.com/LXRCore

    Version: 3.0.0
    Performance Target: 0.00 ms idle (interact points; one hourly rent tick on the server)

    © 2026 iBoss21 / LXRCore | lxrcore.com | All Rights Reserved
]]

Config = Config or {}

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ LANGUAGE ██████████████████████████████████████████████
-- ████████████████████████████████████████████████████████████████████████████████
Config.Lang = 'en'

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ UNIT SIZES (1899 rent per day) ═════════════════════════
-- ████████████████████████████████████████████████████████████████████████████████
Config.Sizes = {
    small  = { slots = 20, weight = 60000,  rent = 0.25 },
    medium = { slots = 40, weight = 150000, rent = 0.60 },
    large  = { slots = 80, weight = 400000, rent = 1.40 },
}

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ YARDS ═════════════════════════════════════════════════
-- ████████████████████████████████████████████████████████████████████████████████
-- keeper: the clerk ped; units: how many of each size; door: where a tenant opens a unit
Config.Yards = {
    { id = 'valentine',  label = 'Valentine Freight Yard',   keeper = { coords = vector3(-338.50, 748.20, 116.10), heading = 90.0, ped = 'u_m_m_valgenstoreowner_01' }, door = vector3(-345.60, 752.10, 116.20), units = { small = 12, medium = 6, large = 2 }, blip = true },
    { id = 'saintdenis', label = 'Saint Denis Bonded Warehouse', keeper = { coords = vector3(2604.70, -1362.40, 46.20), heading = 0.0, ped = 'u_m_m_sdcustomsexchanger_01' }, door = vector3(2598.30, -1358.10, 46.20), units = { small = 20, medium = 10, large = 6 }, blip = true, priceMult = 1.3 },
    { id = 'blackwater', label = 'Blackwater Storage',        keeper = { coords = vector3(-812.40, -1283.20, 43.60), heading = 180.0, ped = 'u_m_m_bwtstablehand_01' }, door = vector3(-818.10, -1279.50, 43.60), units = { small = 10, medium = 4, large = 2 }, blip = true },
}

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ THE BOOK ══════════════════════════════════════════════
-- ████████████████████████████████████████████████████████████████████████████████
Config.Rent = {
    account = 'cash',            -- what the keeper takes
    maxDays = 30,                -- rent ahead at most
    graceDays = 30,              -- padlocked (no access) after rent runs out; cleared after this many more days
    keys = 3,                    -- other citizens a tenant may give a key to
    maxUnitsPerCitizen = 2,
    upgradeKeepsDays = true,     -- moving to a bigger unit keeps the paid days (the difference is charged)
}

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ THE LAW ═══════════════════════════════════════════════
-- ████████████████████████████████████████████████████████████████████████████████
-- a lawman on duty may search any rented unit from the door; the tenant is told, the search is logged
Config.Search = { enabled = true, jobTypes = { 'leo', 'federal' }, minGrade = 1, onDuty = true, tellTenant = true }

Config.Security = { rateLimit = { windowMs = 2000, burst = 6 }, maxDistance = 4.0, promptDistance = 2.5 }
Config.Debug = { printBanner = true, log = true }
