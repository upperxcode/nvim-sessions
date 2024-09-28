local M = {}

-- Função para obter o caminho absoluto do diretório de traduções
function M.get_translation_path(custom_path)
    -- Supondo que você saiba o diretório base dos plugins
    local plugin_base_path = vim.fn.stdpath('data') .. '/site/pack/packer/start/nvim-sessions/lua/nvim-sessions/'
    local default_path = plugin_base_path .. 'translations.json'
    
    return custom_path or default_path
end

-- Função para carregar traduções de um arquivo JSON
local function load_translations(file_path)
    local file = io.open(file_path, "r")
    if not file then
        return nil, "Erro ao abrir o arquivo de traduções."
    end

    local content = file:read("*a")
    file:close()

    local translations = vim.json.decode(content)
    return translations
end

-- Função para inicializar as traduções
function M.init_translations(custom_path)
    --local path = M.get_translation_path(custom_path)
    print(custom_path)
    local path = custom_path
    local translations, err = load_translations(path)
    if not translations then
        print(err)
        return {}
    end
    return translations
end

return M
