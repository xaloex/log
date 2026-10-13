--// LuArmor main source dumper | runtime: Delta exploit, Luau
--// запуск ПОСЛЕ tracer, перед таргет-скриптом:
--// loadstring(game:HttpGet("URL/logdump_dumper.lua"))()

local LOG_FOLDER = "logdump"
local DUMP_FILE = LOG_FOLDER .. "/main_dump.lua"
local META_FILE = LOG_FOLDER .. "/main_meta.log"
local MAX_DUMP = 1000000

pcall(function()
    if makefolder and not isfolder(LOG_FOLDER) then makefolder(LOG_FOLDER) end
end)

local function logMeta(s)
    if appendfile then pcall(appendfile, META_FILE, tostring(s) .. "\n")
    elseif writefile then
        local old = ""
        if isfile and isfile(META_FILE) then pcall(function() old = readfile(META_FILE) end) end
        pcall(writefile, META_FILE, old .. tostring(s) .. "\n")
    else warn("[dumper] " .. tostring(s)) end
end

local function saveDump(src, tag)
    src = tostring(src or "")
    if #src == 0 then logMeta("[SKIP] empty " .. tostring(tag)) return end
    if #src > MAX_DUMP then
        logMeta("[WARN] dump cut " .. #src .. " -> " .. MAX_DUMP .. " tag=" .. tostring(tag))
        src = src:sub(1, MAX_DUMP)
    end
    if writefile then pcall(writefile, DUMP_FILE, src)
    elseif appendfile then pcall(appendfile, DUMP_FILE, src) end
    logMeta("[SAVED] tag=" .. tostring(tag) .. " len=" .. #src .. " -> " .. DUMP_FILE)
    print("[dumper] saved " .. #src .. " bytes tag=" .. tostring(tag))
end

local function looksLikeLua(s)
    s = tostring(s or "")
    if #s < 50 then return false end
    local score = 0
    for _, pat in ipairs({"function", "local ", "end", "return", "game", "Instance", "loadstring", "require"}) do
        if s:find(pat, 1, true) then score += 1 end
    end
    return score >= 3
end

-- 1. перехват возвратов http_request / request / syn.request / http.request
local function hookRet(name, root)
    local f = root and root[name]
    if type(f) ~= "function" then return end
    root[name] = function(opts, ...)
        local res = f(opts, ...)
        local body = nil
        if type(res) == "table" then body = res.Body or res.body or res.Content or res.content end
        if type(res) == "string" then body = res end
        if type(body) == "string" and looksLikeLua(body) then
            local url = type(opts) == "table" and (opts.Url or opts.url) or tostring(opts)
            logMeta("[RET] fn=" .. name .. " url=" .. tostring(url):sub(1, 200) .. " bodylen=" .. #body)
            saveDump(body, name)
        end
        return res
    end
    logMeta("[HOOK] ret " .. name)
end

hookRet("request", getgenv())
hookRet("http_request", getgenv())
hookRet("request", _G)
hookRet("http_request", _G)
if syn then hookRet("request", syn) end
if http then hookRet("request", http) end

-- 2. перехват loadstring/load: последний большой чанк = деобфусцированный main
local origLS = loadstring or load
local origLoad = load
local n = 0
local function hookLoad(tag, orig)
    return function(src, chunk, ...)
        src = tostring(src or "")
        n += 1
        logMeta("[LOAD] #" .. n .. " tag=" .. tag .. " chunk=" .. tostring(chunk) .. " len=" .. #src)
        if looksLikeLua(src) and #src > 2000 then
            saveDump(src, tag .. "_load" .. n)
        end
        return orig(src, chunk, ...)
    end
end
if origLS then getgenv().loadstring = hookLoad("loadstring", origLS) end
if origLoad then getgenv().load = hookLoad("load", origLoad) end

-- 3. перехват string.dump / getscriptbytecode если обфускатор протащит байткод
if getgenv().getscriptbytecode then
    logMeta("[INFO] getscriptbytecode present")
end

logMeta("=== DUMPER ON " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===")
print("[dumper] on. dump -> " .. DUMP_FILE)
print("[dumper] теперь запускай таргет-скрипт, потом скинь " .. DUMP_FILE .. " + " .. META_FILE)
