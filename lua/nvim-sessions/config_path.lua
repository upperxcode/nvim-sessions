-- Definição da tabela de configuração
local ConfigPath = {}

-- Função para normalizar o caminho
function ConfigPath.normalize_path(path)
    -- Substitui barras invertidas por barras normais e remove barras duplicadas
    path = path:gsub('\\', '/'):gsub('/+', '/')
    -- Remove a barra final, se houver
    return path:gsub('(.)/$', '%1')
end

-- Função para obter o caminho completo de configuração
function ConfigPath.get_full_config_path(base_path, relative_path)
    -- Caminhos potenciais para gerenciadores de plugins
    local lazy_path = base_path .. '/lazy'
    local packer_path = base_path .. '/site/pack/packer/start'
	
    -- Verifica qual gerenciador de plugins está presente
    local plugin_manager_path
    if vim.fn.isdirectory(lazy_path) == 1 then
        plugin_manager_path = lazy_path
    elseif vim.fn.isdirectory(packer_path) == 1 then
        plugin_manager_path = packer_path
    else
        -- Caso nenhum dos gerenciadores esteja presente, usa o base_path
        plugin_manager_path = base_path
    end

    -- Concatena o caminho do gerenciador de plugins com o caminho relativo e normaliza o resultado
    local full_path = ConfigPath.normalize_path(plugin_manager_path) .. '/' .. ConfigPath.normalize_path(relative_path)

    -- Retorna o caminho completo normalizado
    return full_path
end

-- Retorna a tabela de configuração para ser usada em outros arquivos
return ConfigPath
