local sessions = {}
local Path = require("plenary.path")
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local scan = require('plenary.scandir')
local translations_module = require('nvim-sessions.translate')

local translations = {}

-- Variáveis configuráveis
local config = {
    custom_path = '/home/media/dev/projetos/.workspaces',
    translate_path = vim.fn.stdpath('data') .. '/site/pack/packer/start/nvim-sessions/lua/nvim-sessions/',
    language = 'en',  -- Idioma padrão
    auto_save = true, -- Salvar sessão automaticamente ao sair
    auto_load = true, -- Carregar sessão automaticamente ao iniciar
    
}

-- Função de configuração
function sessions.setup(user_config)
    config = vim.tbl_extend('force', config, user_config or {})
    update_session_base_path()

    -- Configurar autocommands para salvar e carregar sessões automaticamente
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



local translations = translations_module.init_translations(config.translate_path)


local function translate(key, lang)
    return translations[key] or key
end

-- Carregar traduções ao iniciar
load_translations(config.language)


local session_base_path

-- Função para atualizar o caminho base da sessão
local function update_session_base_path()
    session_base_path = config.custom_path
end



-- Garante que o diretório base exista, criando-o se necessário
local function ensure_base_path_exists()
    if vim.fn.isdirectory(config.custom_path) == 0 then
        vim.fn.mkdir(config.custom_path, "p")
        vim.notify(translate("DIRECTORY_BASE_CREATED", config.language) .. config.custom_path, vim.log.levels.INFO)
    end
end

-- Função auxiliar para notificar erros
local function notify_error(msg1, msg2)
	if msg2 == nil then
		msg2 = ""
	end
    vim.notify(translate(msg, config.language) .. msg2, vim.log.levels.ERROR)
end

-- Função auxiliar para notificar informações
local function notify_info(msg1, msg2)
	if msg2 == nil then
		msg2 = ""
	end
    vim.notify(translate(msg1, config.language) .. msg2, vim.log.levels.INFO)
end

-- Salva informações da sessão em um arquivo oculto
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

-- Fecha todos os buffers abertos
local function close_all_buffers()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) then
            vim.api.nvim_buf_delete(buf, { force = true })
        end
    end
    notify_info("ALL_BUFFERS_CLOSED")
end

-- Função para salvar uma sessão em um diretório selecionado
local function save_session_in_directory(selected_dir)
    if session_base_path == config.custom_path then
        return notify_error("ERROR_INVALID_WORKSPACE")
    end

    if not selected_dir then
        return notify_error("ERROR_INVALID_DIRECTORY")
    end

    local session_name = vim.fn.fnamemodify(selected_dir, ":t")
    local session_path = session_base_path .. '/' .. session_name .. '.vim'

    close_all_buffers()
    vim.cmd('cd ' .. selected_dir)
    
    local response = translate("RESPONSE", config.translate)

    if vim.fn.input(translate("CONFIRM_ADD_CURRENT_WORKSPACE", config.translate), response):lower() == response then
        if vim.fn.filereadable(session_path) == 0 then
            vim.cmd('mksession! ' .. session_path)
            notify_info("SESSION_CREATED", session_path)
        else
            notify_info("EXISTING_SESSION_LOADED", session_path)
        end
        vim.cmd('source ' .. session_path)
        vim.g.loaded_session_path = session_path
    end

    save_session_info()
end

-- Abre o navegador de arquivos do Telescope e salva a sessão
function sessions.open_file_browser_and_save_session()
    require('telescope').extensions.file_browser.file_browser({
        prompt_title = translate("SELECT_DIRECTORY", config.translate),
        cwd = vim.fn.getcwd(),
        hidden = true,
        grouped = true,
        initial_mode = "normal",
        attach_mappings = function(prompt_bufnr, map)
            local save_session = function()
                local current_picker = action_state.get_current_picker(prompt_bufnr)
                local selected_dir = current_picker.finder.path
                actions.close(prompt_bufnr)
                save_session_in_directory(selected_dir)
            end

            map('i', '<C-p>', save_session)
            map('n', '<C-p>', save_session)

            return true
        end,
    })
end

-- Salva a sessão diretamente com o nome da pasta atual
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

-- Carrega uma sessão usando o Telescope
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

-- Define o caminho da sessão
function sessions.set_session_path(subfolder)
    ensure_base_path_exists()
    session_base_path = subfolder and config.custom_path .. '/' .. subfolder or config.custom_path
    notify_info("NEW_SESSION_PATH", session_base_path)
end

-- Carrega informações da sessão de um arquivo oculto
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

-- Deleta uma sessão usando o Telescope
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

-- Cria uma nova subpasta no caminho base
function sessions.create_subfolder()
    ensure_base_path_exists()

    vim.ui.input({ prompt == translate("NEW_SUBFOLDER_NAME", config.translate) }, function(subfolder)
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

-- Lista subpastas e seleciona uma com o Telescope
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

-- Função para obter o workspace atual
function sessions.get_current_workspace()
    return session_base_path
end

-- Função para obter o caminho atual
function sessions.get_current_path()
    return vim.fn.getcwd()
end

-- Função para obter o nome do diretório do projeto
function sessions.get_project_directory_name()
    return vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
end

return sessions
