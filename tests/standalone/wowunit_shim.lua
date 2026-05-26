-- tests/standalone/wowunit_shim.lua
-- Emuliert die WoWUnit-API so dass bestehende *_Test.lua unverändert laufen.
-- Sammelt Test-Suites und registriert sie nach ADDON_LOADED bei busted.

local _suites = {}  -- { { name, tests = { {name, fn} } } }

WoWUnit = setmetatable({}, {
    __call = function(_, suiteName)
        local suite = { _name = suiteName, _tests = {} }
        table.insert(_suites, suite)
        return setmetatable(suite, {
            __newindex = function(t, k, v)
                if type(v) == "function" then
                    table.insert(t._tests, { name = k, fn = v })
                else
                    rawset(t, k, v)
                end
            end,
        })
    end,
})

WoWUnit.AreEqual = function(expected, actual)
    assert(expected == actual,
        string.format("AreEqual failed: expected %s, got %s",
            tostring(expected), tostring(actual)))
end

WoWUnit.IsTrue = function(val)
    assert(val == true,
        string.format("IsTrue failed: got %s", tostring(val)))
end

WoWUnit.IsFalse = function(val)
    assert(not val,
        string.format("IsFalse failed: got %s", tostring(val)))
end

WoWUnit.Exists = function(val)
    assert(val ~= nil and val ~= false,
        string.format("Exists failed: got %s", tostring(val)))
end

-- Pending-Marker: busteds eingebautes pending() ist nur als Top-Level
-- Test-Definer verfügbar (pending(name, fn) statt it(name, fn)), nicht
-- für inline-Skip im laufenden Test. Wir sammeln die Aufrufe stattdessen
-- und drucken eine Liste am Ende der Suite.
local _pendingMarks = {}
local _currentTestName = nil

--- Markiert den aktuell laufenden Test als pending (in busted: Sammel-Eintrag
--- in der Zusammenfassung; in-game WoWUnit: No-Op).
WoWUnit.Pending = function(reason)
    if _currentTestName then
        table.insert(_pendingMarks, {
            test = _currentTestName,
            reason = reason or "no reason",
        })
    end
end

-- Wird von spec/reqrt_spec.lua aufgerufen nachdem ADDON_LOADED gefeuert wurde.
function WoWUnit.RegisterWithBusted(descFn, itFn)
    for _, suite in ipairs(_suites) do
        descFn(suite._name, function()
            for _, t in ipairs(suite._tests) do
                local fn = t.fn
                local fullName = suite._name .. " > " .. t.name
                itFn(t.name, function()
                    _currentTestName = fullName
                    local ok, err = pcall(fn)
                    _currentTestName = nil
                    if not ok then error(err, 0) end
                end)
            end
        end)
    end

    -- Sammel-Suite: läuft nach allen anderen, druckt die pending-Liste.
    descFn("Pending Marks", function()
        itFn("pending tests (silent successes guarded against missing implementations)", function()
            if #_pendingMarks == 0 then
                return  -- nichts pending → still
            end
            io.write("\n")
            for _, p in ipairs(_pendingMarks) do
                io.write(string.format("    - %s: %s\n", p.test, p.reason))
            end
            io.write(string.format("    (%d pending mark(s) total)\n", #_pendingMarks))
        end)
    end)
end
