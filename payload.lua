--// stage5 ret-hook | runtime: Delta, Luau
--// главный сурс уже расшифрован ВНУТРИ VM-функции #4, но наружу торчат
--// только хендлеры (move/bxor/yield). ловим то, что VM ВОЗВРАЩАЕТ и ВЫЗЫВАЕТ.2

local LOG = "logdump"
pcall(function() if makefolder and not isfolder(LOG) then makefolder(LOG) end end)
local function w(p, d) if writefile then pcall(writefile, p, d) end end
local function a(p, s)
    s = tostring(s)
    if appendfile then pcall(appendfile, p, s)
    elseif writefile then
        local old = ""
        if isfile and isfile(p) then pcall(function() old = readfile(p) end) end
        pcall(writefile, p, old .. s)
    end
end
local META = LOG .. "/stage5_meta.log"
a(META, "\n=== STAGE5 ON " .. os.date("%H:%M:%S") .. " ===\n")

-- 1. хук load: оборачиваем КАЖДУЮ возвращённую функцию раппером,
--    который логирует входные аргументы и возвраты (там главный сурс)
local origLS = loadstring
local n = 0
local function looksLua(v)
    if type(v) ~= "string" then return false end
    if #v < 200 then return false end
    local s = 0
    for _, k in ipairs({"function","local","game","Instance","Fire","Remote","Players"}) do
        if v:find(k, 1, true) then s += 1 end
    end
    return s >= 2
end

local function wrapRet(fn, id)
    return function(...)
        local args = {...}
        -- логируем строковые аргументы >200 символов (туда VM суёт расшифрованный код)
        for i, v in ipairs(args) do
            if type(v) == "string" and #v > 500 then
                w(LOG .. "/ret_arg_" .. id .. "_" .. i .. ".lua", v)
                a(META, "[ARG] fn#" .. id .. " arg" .. i .. " len=" .. #v .. "\n")
            end
        end
        local res = table.pack(fn(...))
        for i, v in ipairs(res) do
            if type(v) == "string" and #v > 500 then
                w(LOG .. "/ret_val_" .. id .. "_" .. i .. ".lua", v)
                a(META, "[RET] fn#" .. id .. " ret" .. i .. " len=" .. #v .. "\n")
            elseif type(v) == "function" then
                -- вложенная функция из VM — потрошим константы
                if getconstants then
                    local ok, cs = pcall(getconstants, v)
                    if ok and type(cs) == "table" and #cs > 3 then
                        local buf = {}
                        for j, c in ipairs(cs) do buf[#buf+1] = j .. " [" .. type(c) .. "] " .. tostring(c):sub(1,300) end
                        w(LOG .. "/ret_fnconst_" .. id .. "_" .. i .. ".txt", table.concat(buf, "\n"))
                        a(META, "[RET-FN] fn#" .. id .. " ret" .. i .. " consts=" .. #cs .. "\n")
                    end
                end
            end
        end
        return table.unpack(res)
    end
end

if origLS then
    getgenv().loadstring = function(src, chunk, ...)
        n += 1
        local id = n
        local fn, err = origLS(src, chunk, ...)
        if fn then
            a(META, "[WRAP] #" .. id .. " chunk=" .. tostring(chunk) .. " len=" .. #tostring(src or "") .. "\n")
            -- оборачиваем только большие VM-чанки (3,4), мелочь пропускаем как есть
            if #tostring(src or "") > 100000 then
                return wrapRet(fn, id), err
            end
        end
        return fn, err
    end
end

-- 2. хук task.spawn / coroutine.resume: VM часто стартует главный поток через них
--    логируем какую функцию туда пихают
local function hookSpawn(name, root)
    -- task и coroutine закрыты readonly: пробуем rawset, не вышло — скип без ошибки
    local f = root and root[name]
    if type(f) ~= "function" then return end
    local wrapper = function(fn, ...)
        if type(fn) == "function" and getconstants then
            local ok, cs = pcall(getconstants, fn)
            if ok and type(cs) == "table" and #cs > 5 then
                n += 1
                local buf = {}
                for j, c in ipairs(cs) do buf[#buf+1] = j .. " [" .. type(c) .. "] " .. tostring(c):sub(1,300) end
                w(LOG .. "/spawn_" .. n .. ".txt", table.concat(buf, "\n"))
                a(META, "[SPAWN] " .. name .. " consts=" .. #cs .. " -> spawn_" .. n .. ".txt\n")
            end
        end
        return f(fn, ...)
    end
    if rawset then pcall(rawset, root, name, wrapper)
    else pcall(function() root[name] = wrapper end) end
    a(META, "[HOOK-TRY] " .. name .. "\n")
    return
end
hookSpawn("spawn", task)
hookSpawn("defer", task)
if coroutine then
    local o = coroutine.resume
    local w2 = function(fn, ...)
        if type(fn) == "function" and getconstants then
            local ok, cs = pcall(getconstants, fn)
            if ok and type(cs) == "table" and #cs > 5 then
                n += 1
                local buf = {}
                for j, c in ipairs(cs) do buf[#buf+1] = j .. " [" .. type(c) .. "] " .. tostring(c):sub(1,300) end
                w(LOG .. "/coresume_" .. n .. ".txt", table.concat(buf, "\n"))
                a(META, "[CORESUME] consts=" .. #cs .. " -> coresume_" .. n .. ".txt\n")
            end
        end
        return o(fn, ...)
    end
    if rawset then pcall(rawset, coroutine, "resume", w2)
    else pcall(function() coroutine.resume = w2 end) end
    a(META, "[HOOK-TRY] coroutine.resume\n")
end

print("[stage5] on. запускай таргет, жди, кидай logdump")
