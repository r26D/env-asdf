-- env-asdf plugin for Claudette.
--
-- Detects `.tool-versions` in the worktree root. On export, discovers
-- asdf's installation paths via `asdf info`, then builds a PATH with
-- the shims directory prepended so asdf-managed tools take precedence.

local M = {}

local function join(dir, name)
    return dir .. "/" .. name
end

local function worktree_of(args)
    return (args and args.worktree) or host.workspace().worktree_path
end

local CONFIG_FILES = { ".tool-versions" }

function M.detect(args)
    local wt = worktree_of(args)
    for _, name in ipairs(CONFIG_FILES) do
        if host.file_exists(join(wt, name)) then
            return true
        end
    end
    return false
end

function M.export(args)
    local info = host.exec("asdf", { "info" })
    if info.code ~= 0 then
        error("asdf info failed: " .. (info.stderr or info.stdout or "unknown error"))
    end

    local asdf_dir = info.stdout:match("ASDF_DIR=([^\r\n]+)")
    if not asdf_dir then
        error("could not determine ASDF_DIR from `asdf info` output")
    end
    local data_dir = info.stdout:match("ASDF_DATA_DIR=([^\r\n]+)") or asdf_dir

    local shims_dir = join(data_dir, "shims")
    local bin_dir = join(asdf_dir, "bin")

    -- Read the baseline PATH that the host provided to this process.
    local base_path = ""
    local path_result = host.exec("printenv", { "PATH" })
    if path_result.code == 0 then
        base_path = (path_result.stdout or ""):match("^%s*(.-)%s*$") or ""
    end

    -- Prepend asdf directories, deduplicating against the base.
    local seen = {}
    local dirs = {}
    local function add(dir)
        if dir and #dir > 0 and not seen[dir] then
            seen[dir] = true
            dirs[#dirs + 1] = dir
        end
    end

    add(shims_dir)
    add(bin_dir)
    for dir in base_path:gmatch("[^:]+") do
        add(dir)
    end

    local watched = {}
    local wt = worktree_of(args)
    for _, name in ipairs(CONFIG_FILES) do
        local path = join(wt, name)
        if host.file_exists(path) then
            watched[#watched + 1] = path
        end
    end

    return {
        env = {
            ASDF_DIR = asdf_dir,
            ASDF_DATA_DIR = data_dir,
            PATH = table.concat(dirs, ":"),
        },
        watched = watched,
    }
end

return M
