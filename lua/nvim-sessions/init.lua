local sessions = {}
local Path = require("plenary.path")
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local scan = require('plenary.scandir')
local translations_module = require('nvim-sessions.translate')
local ConfigPath = require('nvim-sessions.config_path')

local config = {
    custom_path = '~/.workspaces',
    translate_path = ConfigPath.get_full_config_path(vim.fn.stdpath('data'), "nvim-sessions/lua/nvim-sessions"),
    language = 'en',
    auto_save = true,
    auto_load = true,
}

local session_base_path
local translations

local function update_session_base_path()
    session_base_path = config.custom_path
end

local function ensure_base_path_exists()
    if vim.fn.isdirectory(config.custom_path) == 0 then
        vim.fn.mkdir(config.custom_path, "p")
        vim.notify(translate("DIRECTORY_BASE_CREATED", config.language) .. config.custom_path, vim.log.levels.INFO)
    end
end

local function notify_error(msg1, msg2)
    msg2 = msg2 or ""
    vim.notify(translate(msg1, config.language) .. msg2, vim.log.levels.ERROR)
end

local function translate(key, lang)
    return translations[key] or key
end

local function notify_info(msg1, msg2)
    msg2 = msg2 or ""
    print("msg1 "..msg1)
    print("msg2 "..msg2)
    print(config.language)
    vim.notify(translate(msg1, config.language)..msg2, vim.log.levels.INFO)
end


function sessions.setup(user_config)
    config = vim.tbl_extend('force', config, user_config or {})
    update_session_base_path()
    translations = translations_module.init_translations(config.translate_path, config.language)

    if config.auto_save then
        vim.cmd([[
            augroup AutoSaveSession
                autocmd!
                autocmd VimLeavePre * lua require('nvim-sessions').save_session()
            augroup END
        ]])
    end

    if config.auto_load then
        vim.cmd([[
            augroup AutoLoadSession
                autocmd!
                autocmd VimEnter * lua vim.defer_fn(function() require('nvim-sessions').load_session_info() end, 100)
            augroup END
        ]])
    end
end

function sessions.get_current_config()
    return config
end

local function save_session_info()
    local session_info_path = config.custom_path .. "/.session_info"
    local file = io.open(session_info_path, "w")

    if not file then
        return notify_error("ERROR_OPENING_SESSION_FILE")
    end

    file:write("workspace=" .. session_base_path .. "\n")
    file:write("cwd=" .. vim.fn.getcwd() .. "\n")
    file:write("session=" .. (vim.g.loaded_session_path or "") .. "\n")
    file:close()

    notify_info("SESSION_INFORMATION_SAVED", session_info_path)
end

local function close_all_buffers()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) then
            vim.api.nvim_buf_delete(buf, { force = true })
        end
    end
    notify_info("ALL_BUFFERS_CLOSED")
end

function sessions.save_session()
    ensure_base_path_exists()

    if session_base_path == config.custom_path then
        return notify_error("ERROR_INVALID_WORKSPACE")
    end

    require('configs.utils').close_no_name_buffers()

    local session_name = vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
    local session_path = session_base_path .. '/' .. session_name .. '.vim'

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_get_name(buf):lower():match("nvimtree") then
            vim.api.nvim_buf_delete(buf, { force = true })
        end
    end

    if vim.fn.filereadable(session_path) == 1 then
        vim.cmd('mksession! ' .. session_path)
        notify_info("EXISTING_SESSION_UPDATED", session_path)
    else
        vim.cmd('mksession! ' .. session_path)
        notify_info("SESSION_SAVED", session_path)
    end

    vim.g.loaded_session_path = session_path

    save_session_info()
end

function sessions.load_session()
    ensure_base_path_exists()

    local session_files = scan.scan_dir(session_base_path, { depth = 1, add_dirs = false })
    if #session_files == 0 then
        return notify_info("NO_SESSIONS_FOUND", session_base_path)
    end

    require('telescope.pickers').new({}, {
        prompt_title = 'Load Session',
        finder = require('telescope.finders').new_table {
            results = session_files,
            entry_maker = function(entry)
                local session_name = vim.fn.fnamemodify(entry, ":t")
                return { value = session_name, display = session_name, ordinal = session_name }
            end,
        },
        sorter = require('telescope.config').values.generic_sorter({}),
        attach_mappings = function(prompt_bufnr)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                local session_path = session_base_path .. '/' .. selection.value
                vim.cmd('source ' .. session_path)
                vim.g.loaded_session_path = session_path
                save_session_info()
            end)
            return true
        end,
    }):find()
end

function sessions.delete_session()
    ensure_base_path_exists()

    local session_files = scan.scan_dir(session_base_path, { depth = 1, add_dirs = false })
    if #session_files == 0 then
        return notify_info("NO_SESSIONS_FOUND", session_base_path)
    end

    require('telescope.pickers').new({}, {
        prompt_title = 'Delete Session',
        finder = require('telescope.finders').new_table {
            results = session_files,
            entry_maker = function(entry)
                local session_name = vim.fn.fnamemodify(entry, ":t")
                return { value = session_name, display = session_name, ordinal = session_name }
            end,
        },
        sorter = require('telescope.config').values.generic_sorter({}),
        attach_mappings = function(prompt_bufnr)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                local session_path = session_base_path .. '/' .. selection.value

                local confirm = vim.fn.input(translate("CONFIRM_DELETE_SESSION", config.language) .. '"' .. selection.value .. '"' .. translate("CONFIRM_DELETE_SUFFIX", config.language))
                if confirm:lower() ~= 'y' then
                    return notify_info("DELETION_CANCELLED")
                end

                local status_ok, err = pcall(vim.fn.delete, session_path)
                if not status_ok then
                    return notify_error("ERROR_DELETING_SESSION", err)
                end

                notify_info("SESSION_DELETED_SUCCESSFULLY", selection.value)
            end)
            return true
        end,
    }):find()
end

function sessions.load_session_info()
    local session_info_path = config.custom_path .. "/.session_info"
    if vim.fn.filereadable(session_info_path) == 0 then
        return notify_info("NO_SESSION_INFORMATION_FOUND")
    end

    local file = io.open(session_info_path, "r")
    if not file then
        return notify_error("ERROR_OPENING_SESSION_FILE")
    end

    local workspace_path, session_path, cwd
    for line in file:lines() do
        local key, value = line:match("^(%w+)=([^\n]*)")
        if key == "workspace" then workspace_path = value end
        if key == "session" then session_path = value end
        if key == "cwd" then cwd = value end
    end
    file:close()

    session_base_path = workspace_path or session_base_path
    if cwd then vim.cmd('cd ' .. cwd) end

    if session_path and vim.fn.filereadable(session_path) == 1 then
        vim.cmd('source ' .. session_path)
        vim.g.loaded_session_path = session_path
        notify_info("SESSION_LOADED_FROM", session_path)
    end
end

function sessions.set_session_path(subfolder)
    ensure_base_path_exists()
    session_base_path = subfolder and config.custom_path .. '/' .. subfolder or config.custom_path
    notify_info("NEW_SESSION_PATH", session_base_path)
end

function sessions.create_subfolder()
    ensure_base_path_exists()

    vim.ui.input({ prompt = translate("NEW_SUBFOLDER_NAME", config.language) }, function(subfolder)
        if not subfolder or subfolder == '' then
            return notify_error("ERROR_SUBFOLDER_NAME_NOT_PROVIDED")
        end

        local full_path = config.custom_path .. '/' .. subfolder
        if vim.fn.isdirectory(full_path) == 1 then
            return notify_error("ERROR_SUBFOLDER_ALREADY_EXISTS", full_path)
        end

        vim.fn.mkdir(full_path, "p")
        notify_info("SUBFOLDER_CREATED", full_path)

        sessions.set_session_path(subfolder)
    end)
end

function sessions.select_subfolder_with_telescope()
    ensure_base_path_exists()

    local subfolders = scan.scan_dir(config.custom_path, { depth = 1, only_dirs = true })

    if #subfolders == 0 then
        return notify_info("NO_SUBFOLDERS_FOUND", config.custom_path)
    end

    require('telescope.pickers').new({}, {
        prompt_title = 'Select Subfolder',
        finder = require('telescope.finders').new_table {
            results = subfolders,
            entry_maker = function(entry)
                local subfolder_name = vim.fn.fnamemodify(entry, ":t")
                return { value = subfolder_name, display = subfolder_name, ordinal = subfolder_name }
            end,
        },
        sorter = require('telescope.config').values.generic_sorter({}),
        attach_mappings = function(prompt_bufnr)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                sessions.set_session_path(selection.value)
            end)
            return true
        end,
    }):find()
end

function sessions.get_current_workspace()
    return session_base_path
end

function sessions.get_current_path()
    return vim.fn.getcwd()
end

function sessions.get_project_directory_name()
    return vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
end

return sessions
