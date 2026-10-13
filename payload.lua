--// stage4 memdump | runtime: Delta, Luau
--// stage_6 оказался пустышкой-паддингом 16МБ пробелов (антидамп трюк:
--// настоящий VM подменяет чанк в памяти ПОСЛЕ loadstring, а tracer снял заглушку).
--// этот файл хукает loadstring так: компилирует, потом читает РЕАЛЬНУЮ функцию из памяти.

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

local META = LOG_FOLDER .. "/stage4_meta.log"
local n = 0
local origLS = loadstring
local origLoad = load

local function dumpFn(fn, id, chunk, srclen)
    -- 1. константы реальной функции из памяти
    if getconstants then
        local ok, cs = pcall(getconstants, fn)
        if ok and type(cs) == "table" then
            local buf = {"=== CONSTS #" .. id .. " chunk=" .. tostring(chunk) .. " srclen=" .. srclen .. " n=" .. #cs .. " ===\n"}
            for i, c in ipairs(cs) do
                buf[#buf+1] = i .. " [" .. type(c) .. "] " .. tostring(c):sub(1, 400) .. "\n"
            end
            w(LOG_FOLDER .. "/mem_const_" .. id .. ".txt", table.concat(buf))
            a(META, "[CONST] #" .. id .. " n=" .. #cs .. "\n")
        else
            a(META, "[CONST FAIL] #" .. id .. " " .. tostring(cs):sub(1,150) .. "\n")
        end
    end
    -- 2. upvalues реальной функции
    if getupvalues then
        local ok, uvs = pcall(getupvalues, fn)
        if ok and type(uvs) == "table" then
            local buf = {"=== UPV #" .. id .. " n=" .. #uvs .. " ===\n"}
            for i, v in ipairs(uvs) do
                buf[#buf+1] = i .. " [" .. type(v) .. "] " .. tostring(v):sub(1, 400) .. "\n"
            end
            w(LOG_FOLDER .. "/mem_upv_" .. id .. ".txt", table.concat(buf))
            a(META, "[UPV] #" .. id .. " n=" .. #uvs .. "\n")
        end
    end
    -- 3. протосы
    if getprotos then
        local ok, ps = pcall(getprotos, fn)
        if ok and type(ps) == "table" then
            a(META, "[PROTOS] #" .. id .. " n=" .. #ps .. "\n")
            for i, pr in ipairs(ps) do
                if getconstants then
                    local ok2, cs = pcall(getconstants, pr)
                    if ok2 and type(cs) == "table" and #cs > 0 then
                        local strs = {}
                        for _, c in ipairs(cs) do
                            if type(c) == "string" and #c >= 3 and #c <= 300 then strs[#strs+1] = c end
                        end
                        if #strs > 0 then
                            w(LOG_FOLDER .. "/mem_proto_" .. id .. "_" .. i .. ".txt", table.concat(strs, "\n"))
                        end
                    end
                end
            end
        end
    end
    -- 4. дизассемблер если есть
    if getscriptbytecode then
        -- в delta getscriptbytecode хочет Instance; пробуем через getscriptclosure
    end
end

if origLS then
    getgenv().loadstring = function(src, chunk, ...)
        n += 1
        local id = n
        local srclen = #tostring(src or "")
        a(META, "[LOAD] #" .. id .. " chunk=" .. tostring(chunk) .. " srclen=" .. srclen .. "\n")
        -- детект паддинга: если сурс из одних пробелов — метим и всё равно компилим
        local only_spaces = true
        local s = tostring(src or "")
        for i = 1, math.min(#s, 1000) do
            if s:byte(i) ~= 32 and s:byte(i) ~= 10 and s:byte(i) ~= 13 and s:byte(i) ~= 9 then only_spaces = false break end
        end
        if only_spaces and srclen > 1000 then
            a(META, "[PAD] #" .. id .. " spaces-only, real code подменится в памяти\n")
        end
        local fn, err = origLS(src, chunk, ...)
        if fn then
            dumpFn(fn, id, chunk, srclen)
        else
            a(META, "[COMPILE ERR] #" .. id .. " " .. tostring(err):sub(1,200) .. "\n")
        end
        return fn, err
    end
end

a(META, "=== STAGE4 ON " .. os.date("%H:%M:%S") .. " ===\n")
print("[stage4] on. запускай таргет. смотри mem_const_*.txt")
