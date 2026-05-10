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

-- Wird von spec/reqrt_spec.lua aufgerufen nachdem ADDON_LOADED gefeuert wurde.
function WoWUnit.RegisterWithBusted(descFn, itFn)
    for _, suite in ipairs(_suites) do
        descFn(suite._name, function()
            for _, t in ipairs(suite._tests) do
                itFn(t.name, t.fn)
            end
        end)
    end
end
