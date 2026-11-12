-- Offline checks that the Quiz shows question and answer text through ns.L
-- (NaowhForever_QoL/Travel/Quiz.lua), so locale files can translate them.
-- These do not emulate client taint or rendering. Run with Lua 5.1 from the repository root.
local checks = 0
local function check(label, ok) assert(ok, label); checks = checks + 1 end

local function fixture(questions)
    local s = { settings = { enabled = true }, account = {} }
    local any
    local function noop() return any end
    any = setmetatable({}, { __index = function() return noop end })
    local M = {}
    local meta = { __index = function(_, k)
        if M[k] then return M[k] end
        if k:match("^%u") then return noop end
    end }
    local function new(kind, parent)
        return setmetatable({ kind = kind, parent = parent, scripts = {}, shown = true, text = "" }, meta)
    end
    function M:SetScript(k, fn) self.scripts[k] = fn end
    function M:Show() self.shown = true end
    function M:Hide() self.shown = false end
    function M:SetShown(v) self.shown = v and true or false end
    function M:IsShown() return self.shown end
    function M:CreateTexture() return new("Texture", self) end
    function M:SetText(t) self.text = t end
    function M:GetText() return self.text end
    function M:SetTextColor() end
    function M:Enable() end
    function M:Disable() end
    local globals = { NaowhForever = nil }
    local function frame(kind, name, parent)
        local f = new(kind, parent)
        if name then globals[name] = f end
        return f
    end
    local S = {
        Get = function(k) return s.settings[k] end,
        Set = function(k, v) s.settings[k] = v end,
    }
    local translated = {
        ["Question?"] = "Question FR?",
        ["Right"] = "Bonne",
        ["Wrong A"] = "Fausse A",
        ["Wrong B"] = "Fausse B",
        ["Wrong C"] = "Fausse C",
    }
    local ns = {
        L = function(key, ...)
            local text = translated[key] or key
            if select("#", ...) > 0 then return text:format(...) end
            return text
        end,
        QoLSettings = S,
        THEME = { bg = {}, muted = {}, accent = {}, fg = { r = 1, g = 1, b = 1 } },
        Shared = { Style = dofile("Tools/regression/shared_style.lua"),
            Settings = { Page = function() return { Card = function() end } end } },
        QUIZ_QUESTIONS = questions,
        AccountSettings = function() return s.account end,
        AllowOffscreen = function() end,
        Solid = function(parent) return new("Texture", parent) end,
        Border = function(parent) return new("Border", parent) end,
        Font = function(parent) return new("FontString", parent) end,
        Button = function(parent)
            local b = new("Button", parent)
            b.label = new("FontString", b)
            return b
        end,
        RegisterMinimapFeature = function() end,
        Apply = function() end,
        FlightGameHideButton = function(parent)
            local b = new("Button", parent)
            b.shown = false
            return b
        end,
        FlightGameOffered = function() return false end,
    }
    globals.NaowhForever = ns
    local env = setmetatable({
        _G = globals,
        CreateFrame = frame, UIParent = new("Frame"),
        InCombatLockdown = function() return false end,
        hooksecurefunc = function(t, k, fn) local old = t[k]; t[k] = function(...) old(...); fn(...) end end,
    }, { __index = _G })
    local chunk = assert(loadfile("NaowhForever_QoL/Travel/Quiz.lua"))
    setfenv(chunk, env)
    chunk()
    s.ns = ns
    s.globals = globals
    return s
end

local function Shown(quiz)
    local answers = {}
    for _, btn in ipairs(quiz.answers) do
        answers[#answers + 1] = btn.label.text
    end
    return quiz.question.text, answers
end

do
    local s = fixture({
        { q = "Question?", a = { "Right", "Wrong A", "Wrong B", "Wrong C" } },
    })
    s.ns.ToggleQuiz()
    local quiz = s.globals.NaowhForeverQuiz
    check("quiz frame exists after open", quiz ~= nil)
    local question, answers = Shown(quiz)
    local seen = {}
    for _, text in ipairs(answers) do seen[text] = true end
    check("question text goes through ns.L", question == "Question FR?")
    check("right answer goes through ns.L", seen["Bonne"])
    check("wrong answers go through ns.L",
        seen["Fausse A"] and seen["Fausse B"] and seen["Fausse C"])
    check("raw English answers are not shown",
        not seen["Right"] and not seen["Wrong A"] and not seen["Wrong B"] and not seen["Wrong C"])
end

do
    local s = fixture({
        { q = "Unmapped?", a = { "Bare Right", "Bare A", "Bare B", "Bare C" } },
    })
    s.ns.ToggleQuiz()
    local question, answers = Shown(s.globals.NaowhForeverQuiz)
    local seen = {}
    for _, text in ipairs(answers) do seen[text] = true end
    check("unmapped question falls back to the English key", question == "Unmapped?")
    check("unmapped answers fall back to the English keys",
        seen["Bare Right"] and seen["Bare A"] and seen["Bare B"] and seen["Bare C"])
end

print("test-quiz-locale: " .. checks .. " checks passed")
