--[[--
iOS: repair absolute paths after the app's data container moves.

iOS keeps an app's data in a container whose path holds a UUID
(/var/mobile/Containers/Data/Application/<UUID>/Documents), and the UUID can
change when the app is reinstalled or updated. KOReader stores absolute
paths in its settings (home_dir, lastdir, extra_plugin_paths, history,
plugin settings, ...), so after a move they point at a container that no
longer exists: user plugins stop loading, the home folder and history break.

migrate() runs at startup, before any settings are read. When the container
differs from the one recorded at the last launch, it rewrites the UUID in
every path of the form .../Containers/Data/Application/<UUID>/... in the
settings files to the current one. The sandbox blocks access to other apps'
data containers, so any such path in our settings can only be ours.
]]

local lfs = require("libs/libkoreader-lfs")

local M = {}

local UUID = "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x"
local PATTERN = "(/Containers/Data/Application/)(" .. UUID .. ")(/)"

--- Container UUID in a path, or nil.
function M.containerId(path)
    if type(path) ~= "string" then return nil end
    local _, id = path:match(PATTERN)
    return id
end

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

--- Rewrite one file in place (via a temp file). Returns true if it changed.
function M.rewriteFile(path, current)
    local s = readFile(path)
    if not s then return false end
    local changed = false
    local out = s:gsub(PATTERN, function(pre, id, post)
        if id ~= current then changed = true end
        return pre .. current .. post
    end)
    if not changed then return false end
    local tmp = path .. ".ios-migrate"
    local w = io.open(tmp, "wb")
    if not w then return false end
    w:write(out)
    w:close()
    return os.rename(tmp, path) and true or false
end

-- Settings files: the top-level ones plus every *.lua / *.lua.old under
-- settings/ (plugins keep their settings there).
local function settingsFiles(data_dir)
    local files = {}
    for _, name in ipairs({ "settings.reader.lua", "settings.reader.lua.old",
                            "history.lua", "history.lua.old" }) do
        table.insert(files, data_dir .. "/" .. name)
    end
    local function walk(dir)
        local ok, iter, state = pcall(lfs.dir, dir)
        if not ok then return end
        for entry in iter, state do
            if entry ~= "." and entry ~= ".." then
                local p = dir .. "/" .. entry
                local mode = lfs.attributes(p, "mode")
                if mode == "directory" then
                    walk(p)
                elseif mode == "file" and (entry:match("%.lua$") or entry:match("%.lua%.old$")) then
                    table.insert(files, p)
                end
            end
        end
    end
    walk(data_dir .. "/settings")
    return files
end

--- Run once at startup. data_dir is DataStorage:getDataDir().
-- Returns the number of files rewritten.
function M.migrate(data_dir)
    local current = M.containerId(data_dir .. "/")
    if not current then return 0 end
    local marker = data_dir .. "/settings/.ios_container_id"
    local last = readFile(marker)
    if last and last:match("^%s*(.-)%s*$") == current then return 0 end

    local n = 0
    for _, path in ipairs(settingsFiles(data_dir)) do
        if M.rewriteFile(path, current) then
            n = n + 1
            io.write("[ios container] updated paths in ", path, "\n")
        end
    end

    if lfs.attributes(data_dir .. "/settings", "mode") == "directory" then
        local w = io.open(marker, "wb")
        if w then
            w:write(current, "\n")
            w:close()
        end
    end
    if last then
        io.write("[ios container] container moved from ", last:match("^%s*(.-)%s*$"),
                 " to ", current, "; rewrote ", n, " file(s)\n")
    end
    return n
end

return M
