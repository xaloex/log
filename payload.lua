--// stage3 runtime const/upvalue dumper | runtime: Delta, Luau
--// цель: stage_6 (16МБ, Luraph VM) — вытащить константы/строки/ремоты наружу
--// запуск: сначала stage2 уже снял stage_N.lua. потом:
--//   1. открой stage_6.lua начало — найди главную функцию чанка
--//   2. запусти ЭТОТ файл вместо таргета, он сам загрузит stage_6 и просканирует

local LOG_FOLDER = "logdump"
pcall(function() if makefolder and not isfolder(LOG_FOLDER) then makefolder(LOG_FOLDER) end end)

local function w(path, data)
    if writefile then pcall(writefile, path, data) end
end
local function a(path, s)
    s = tostring(s)
    if appendfile then pcall(appendfile, path, s)
    elseif writefile then
        local old = ""
        if isfile and isfile(path) then pcall(function() old = readfile(path) end) end
        pcall(writefile, path, old .. s)
    end
end

local META = LOG_FOLDER .. "/stage3_meta.log"
local OUT = LOG_FOLDER .. "/const_dump.txt"

local function readStage(n)
    local p = LOG_FOLDER .. "/stage_" .. n .. ".lua"
    if isfile and not isfile(p) then return nil end
    local ok, src = pcall(readfile, p)
    if ok then return src end
    return nil
end

-- собрать все строки/константы статикой из сурса stage_6
local src6 = readStage(6)
if not src6 then
    a(META, "[ERR] no stage_6.lua\n")
    print("[stage3] нет stage_6.lua")
    return
end
a(META, "[INFO] stage6 len=" .. #src6 .. "\n")

-- 1. статический проход: все строки в кавычках длиннее 3 символов
local seen = {}
local count = 0
w(OUT, "=== CONST DUMP stage_6 len=" .. #src6 .. " ===\n")
for s in src6:gmatch("[\"']([^\"'\n]-)[\"']") do
    if #s >= 4 and #s <= 500 and not seen[s] then
        seen[s] = true
        count += 1
        -- фильтруем мусор из пробелов
        if not s:match("^%s+$") then
            a(OUT, "[" .. count .. "] " .. s .. "\n")
        end
    end
end
a(META, "[STATIC] strings=" .. count .. "\n")

-- 2. GetService / RemoteEvent / FireServer вызовы — точки входа
local hits = {}
for svc in src6:gmatch("GetService%(%s*[\"']([^\"']+)[\"']") do
    hits["service:" .. svc] = true
end
for rem in src6:gmatch("WaitForChild%(%s*[\"']([^\"']+)[\"']") do
    hits["child:" .. rem] = true
end
for _, pat in ipairs({"FireServer", "InvokeServer", "Fire", "Invoke", "Kick", "Teleport"}) do
    if src6:find(pat, 1, true) then hits["call:" .. pat] = true end
end
a(OUT, "\n=== ENTRYPOINTS ===\n")
for k in pairs(hits) do a(OUT, k .. "\n") end

-- 3. рантайм: грузим stage_6 БЕЗ запуска, копаем upvalues/consts главной fn
local fn, err = loadstring(src6, "stage6")
if not fn then
    a(META, "[LOAD ERR] " .. tostring(err) .. "\n")
    print("[stage3] load err, смотри meta")
    return
end

-- константы через getconstants если есть
if getconstants then
    local ok, consts = pcall(getconstants, fn)
    if ok and type(consts) == "table" then
        a(OUT, "\n=== GETCONSTANTS n=" .. #consts .. " ===\n")
        for i, c in ipairs(consts) do
            a(OUT, i .. " [" .. type(c) .. "] " .. tostring(c):sub(1, 300) .. "\n")
        end
    else
        a(META, "[CONST FAIL] " .. tostring(consts):sub(1, 200) .. "\n")
    end
else
    a(META, "[INFO] no getconstants\n")
end

-- upvalues
if debug and debug.getupvalue then
    a(OUT, "\n=== UPV VALUES ===\n")
    local i = 1
    while true do
        local ok, name, val = pcall(debug.getupvalue, fn, i)
        if not ok or not name then break end
        a(OUT, i .. " " .. tostring(name) .. " [" .. type(val) .. "] " .. tostring(val):sub(1, 300) .. "\n")
        i += 1
        if i > 100 then break end
    end
end

-- getupvalues (exploit api)
if getupvalues then
    local ok, uvs = pcall(getupvalues, fn)
    if ok and type(uvs) == "table" then
        a(OUT, "\n=== GETUPVALUES n=" .. #uvs .. " ===\n")
        for i, v in ipairs(uvs) do
            a(OUT, i .. " [" .. type(v) .. "] " .. tostring(v):sub(1, 300) .. "\n")
        end
    end
end

-- проtos
if getprotos then
    local ok, ps = pcall(getprotos, fn)
    if ok and type(ps) == "table" then
        a(META, "[PROTOS] n=" .. #ps .. "\n")
        a(OUT, "\n=== PROTOS n=" .. #ps .. " ===\n")
        for i, p in ipairs(ps) do
            local cstr = ""
            if getconstants then
                local ok2, cs = pcall(getconstants, p)
                if ok2 and type(cs) == "table" then
                    for _, c in ipairs(cs) do
                        if type(c) == "string" and #c >= 4 and #c <= 200 then
                            cstr ..= "[" .. c .. "] "
                        end
                    end
                end
            end
            a(OUT, "proto " .. i .. " " .. cstr:sub(1, 500) .. "\n")
        end
    end
end

a(META, "=== STAGE3 DONE ===\n")
print("[stage3] done. смотри const_dump.txt + stage3_meta.log")
