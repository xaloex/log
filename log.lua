--// Delta loadstring tracer | runtime: Delta exploit, Luau
--// usage: loadstring(game:HttpGet("URL/logdump_tracer.lua"))() then run target script

local LOG_FOLDER = "logdump"
local LOG_FILE = LOG_FOLDER .. "/trace_" .. os.time() .. ".log"
local MAX_SNIPPET = 5000
local MAX_TOTAL = 200000

local function ensureFolder()
    pcall(function()
        if makefolder and not isfolder(LOG_FOLDER) then
            makefolder(LOG_FOLDER)
        end
    end)
end

local function safeAppend(path, text)
    if appendfile then
        pcall(appendfile, path, text)
    elseif writefile then
        local old = ""
        if isfile and isfile(path) then
            pcall(function() old = readfile(path) end)
        end
        pcall(writefile, path, old .. text)
    else
        warn("[tracer] no write api: " .. text)
    end
end

local function snippet(s, cap)
    cap = cap or MAX_SNIPPET
    s = tostring(s or "")
    if #s > cap then
        return s:sub(1, cap) .. "\n...[CUT len=" .. #s .. "]..."
    end
    return s
end

local function tracebackStr()
    local t = debug and debug.traceback and debug.traceback() or "no debug.traceback"
    return tostring(t)
end

local function callerInfo(level)
    if getinfo then
        local ok, info = pcall(getinfo, level or 3)
        if ok and type(info) == "table" then
            return "src=" .. tostring(info.source) .. " line=" .. tostring(info.currentline)
                .. " func=" .. tostring(info.name or "?") .. " what=" .. tostring(info.what or "?")
        end
    elseif debug and debug.getinfo then
        local ok, info = pcall(debug.getinfo, level or 3)
        if ok and type(info) == "table" then
            return "src=" .. tostring(info.source) .. " line=" .. tostring(info.currentline)
                .. " func=" .. tostring(info.name or "?")
        end
    end
    return "caller=?"
end

ensureFolder()
pcall(safeAppend, LOG_FILE, "=== TRACE START " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")

local origLoadstring = loadstring or load
local origLoad = load

local counter = 0

local function logLoad(chunkname, src, extra)
    counter += 1
    local id = counter
    local srclen = #tostring(src or "")
    local entry = string.format(
        "\n--- [LOAD #%d] time=%s chunk=%s len=%d %s\nCALLER: %s\nTRACE:\n%s\nSOURCE SNIPPET:\n%s\n--- [END #%d] ---\n",
        id, os.date("%H:%M:%S"), tostring(chunkname), srclen, extra or "",
        callerInfo(4), tracebackStr(), snippet(src)
    )
    pcall(safeAppend, LOG_FILE, entry)

    -- полный дамп чанка отдельно, без обрезки до капа
    if srclen > 0 and srclen <= MAX_TOTAL then
        pcall(safeAppend, LOG_FOLDER .. "/chunk_" .. id .. ".lua", tostring(src))
    elseif srclen > MAX_TOTAL then
        pcall(safeAppend, LOG_FOLDER .. "/chunk_" .. id .. "_part.lua", tostring(src):sub(1, MAX_TOTAL))
        pcall(safeAppend, LOG_FILE, "[NOTE] chunk #" .. id .. " cut to " .. MAX_TOTAL .. " bytes\n")
    end
    return id
end

-- перехват loadstring
if origLoadstring then
    getgenv().loadstring = function(src, chunk, ...)
        local okLog = pcall(logLoad, chunk or "loadstring", src, "")
        local fn, err = origLoadstring(src, chunk, ...)
        if not fn then
            pcall(safeAppend, LOG_FILE, "[COMPILE ERR] " .. tostring(err) .. "\n")
        end
        return fn, err
    end
    getgenv().load = function(src, chunk, ...)
        local okLog = pcall(logLoad, chunk or "load", src, "")
        local fn, err = origLoad(src, chunk, ...)
        if not fn then
            pcall(safeAppend, LOG_FILE, "[COMPILE ERR] " .. tostring(err) .. "\n")
        end
        return fn, err
    end
end

-- перехват HttpGet / запросов: куда скрипт стучится за главным сурсом
local gameMt = getrawmetatable and getrawmetatable(game)
local oldNamecall
if gameMt and setreadonly then
    setreadonly(gameMt, false)
    oldNamecall = gameMt.__namecall
    gameMt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod and getnamecallmethod() or ""
        if method == "HttpGet" or method == "HttpGetAsync" or method == "GetObjects" then
            local args = {...}
            pcall(safeAppend, LOG_FILE, string.format(
                "\n[HTTP] method=%s url=%s\nCALLER: %s\nTRACE:\n%s\n",
                tostring(method), tostring(args[1]), callerInfo(4), tracebackStr()
            ))
        end
        return oldNamecall(self, ...)
    end)
    setreadonly(gameMt, true)
end

-- перехват request / http_request / syn.request
local function hookReq(name)
    local f = getgenv()[name] or _G[name]
    if type(f) == "function" then
        getgenv()[name] = function(opts, ...)
            local url = type(opts) == "table" and (opts.Url or opts.url) or tostring(opts)
            pcall(safeAppend, LOG_FILE, string.format(
                "\n[REQ] fn=%s url=%s\nCALLER: %s\nTRACE:\n%s\n",
                tostring(name), tostring(url), callerInfo(4), tracebackStr()
            ))
            return f(opts, ...)
        end
    end
end
hookReq("request")
hookReq("http_request")
if syn and syn.request then
    local o = syn.request
    syn.request = function(opts, ...)
        local url = type(opts) == "table" and (opts.Url or opts.url) or tostring(opts)
        pcall(safeAppend, LOG_FILE, "[REQ] fn=syn.request url=" .. tostring(url) .. "\nCALLER: " .. callerInfo(4) .. "\n")
        return o(opts, ...)
    end
end
if http and http.request then
    local o = http.request
    http.request = function(opts, ...)
        local url = type(opts) == "table" and (opts.Url or opts.url) or tostring(opts)
        pcall(safeAppend, LOG_FILE, "[REQ] fn=http.request url=" .. tostring(url) .. "\nCALLER: " .. callerInfo(4) .. "\n")
        return o(opts, ...)
    end
end

-- трекинг созданных скриптов: где деобфусцированный сурс осел
local function watchInstance(cls)
    local orig = Instance and Instance.new
    return orig
end

print("[tracer] on. log: " .. LOG_FILE)
print("[tracer] скинь мне " .. LOG_FOLDER .. "/trace_*.log + chunk_*.lua, напишу точный дампер под главный сурс")
