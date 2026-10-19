local compat = require('render-markdown.lib.compat')
local source = require('render-markdown.integ.source')

---@class render.md.integ.Lsp
local M = {}

---@alias render.md.lsp.Encoding 'utf-8'|'utf-16'|'utf-32'

---@class render.md.lsp.Heading
---@field level integer
---@field name string
---@field start_row integer
---@field start_col integer
---@field sel_start_row integer
---@field sel_start_col integer
---@field sel_end_row integer
---@field sel_end_col integer

---called from state on attach
function M.init()
    local name = 'render-markdown'
    vim.lsp.start({ name = name, cmd = M.server }, {
        bufnr = 0,
        reuse_client = function(client, config)
            return client.name == config.name
        end,
    })
end

---@private
---@param dispatchers vim.lsp.rpc.Dispatchers
---@return vim.lsp.rpc.PublicClient
function M.server(dispatchers)
    local id = 0
    local closing = false
    local encoding = 'utf-16' ---@type render.md.lsp.Encoding

    ---@type vim.lsp.rpc.PublicClient
    return {
        request = function(method, params, callback)
            id = id + 1
            if method == 'initialize' then
                encoding = M.encoding(params)
                callback(nil, {
                    capabilities = {
                        positionEncoding = encoding,
                        completionProvider = {
                            triggerCharacters = source.trigger_characters(),
                        },
                        documentSymbolProvider = true,
                    },
                }, id)
            elseif method == 'textDocument/completion' then
                callback(nil, M.completions(params), id)
            elseif method == 'textDocument/documentSymbol' then
                callback(nil, M.document_symbols(params, encoding), id)
            elseif method == 'shutdown' then
                callback(nil, nil, id)
            end
            return true, id
        end,
        notify = function(method)
            if method == 'exit' then
                -- code 0 (success), signal 15 (SIGTERM)
                dispatchers.on_exit(0, 15)
            end
            return true
        end,
        is_closing = function()
            return closing
        end,
        terminate = function()
            closing = true
        end,
    }
end

---@private
---@param params lsp.InitializeParams?
---@return render.md.lsp.Encoding
function M.encoding(params)
    local offered = params
        and params.capabilities
        and params.capabilities.general
        and params.capabilities.general.positionEncodings
    if type(offered) ~= 'table' then
        return 'utf-16'
    end
    if vim.tbl_contains(offered, 'utf-8') then
        return 'utf-8'
    elseif vim.tbl_contains(offered, 'utf-16') then
        return 'utf-16'
    elseif vim.tbl_contains(offered, 'utf-32') then
        return 'utf-32'
    end
    return 'utf-16'
end

---@private
---@param params lsp.CompletionParams
---@return lsp.CompletionList?
function M.completions(params)
    -- lsp position: (0,0)-indexed
    local cursor = params.position
    local items = source.items(0, cursor.line, cursor.character)
    if not items then
        return nil
    end
    ---@type lsp.CompletionList
    return {
        isIncomplete = false,
        items = items,
    }
end

---@private
---@param params lsp.DocumentSymbolParams
---@param encoding render.md.lsp.Encoding
---@return lsp.DocumentSymbol[]?
function M.document_symbols(params, encoding)
    local uri = params and params.textDocument and params.textDocument.uri
    if not uri then
        return nil
    end
    local buf = M.buf(uri)
    if not buf then
        return nil
    end
    return M.symbols(buf, encoding)
end

---Heading outline. A heading owns the lines up to the next heading of the
---same or higher level. Deeper headings are nested underneath it.
---@param buf integer
---@param encoding render.md.lsp.Encoding
---@return lsp.DocumentSymbol[]?
function M.symbols(buf, encoding)
    if buf == 0 then
        buf = vim.api.nvim_get_current_buf()
    end
    local ok, parser = pcall(vim.treesitter.get_parser, buf, 'markdown')
    if not ok or not parser then
        return nil
    end
    local trees = parser:parse()
    local root = trees and trees[1] and trees[1]:root()
    if not root then
        return nil
    end
    return M.hierarchy(buf, M.headings(buf, root), root, encoding)
end

---@private
---@param uri string
---@return integer?
function M.buf(uri)
    local current = vim.api.nvim_get_current_buf()
    if
        vim.api.nvim_buf_is_loaded(current)
        and vim.uri_from_bufnr(current) == uri
    then
        return current
    end
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if
            vim.api.nvim_buf_is_loaded(buf)
            and vim.uri_from_bufnr(buf) == uri
        then
            return buf
        end
    end
    return nil
end

---@private
---@param buf integer
---@param root TSNode
---@return render.md.lsp.Heading[]
function M.headings(buf, root)
    local result = {} ---@type render.md.lsp.Heading[]
    local function walk(node)
        local kind = node:type()
        if kind == 'atx_heading' or kind == 'setext_heading' then
            local heading = M.heading(buf, node)
            if heading then
                result[#result + 1] = heading
            end
            return
        end
        for child in node:iter_children() do
            walk(child)
        end
    end
    walk(root)
    return result
end

---@private
---@param buf integer
---@param node TSNode
---@return render.md.lsp.Heading?
function M.heading(buf, node)
    local level = M.level(node)
    local title = M.title(node)
    if not level or not title then
        return nil
    end
    local text = vim.treesitter.get_node_text(title, buf)
    local sel_start_row, sel_start_col, sel_end_row, sel_end_col = title:range()
    if node:type() == 'atx_heading' then
        -- CommonMark drops a trailing " #" sequence from the heading text.
        local closing = text:match('%s+#+%s*$')
        if closing then
            text = text:sub(1, #text - #closing)
            if sel_end_row == sel_start_row then
                sel_end_col = math.max(sel_start_col, sel_end_col - #closing)
            end
        end
    end
    local name = vim.trim(text:gsub('%s+', ' '))
    if name == '' then
        return nil
    end
    local start_row, start_col = node:range()
    ---@type render.md.lsp.Heading
    return {
        level = level,
        name = name,
        start_row = start_row,
        start_col = start_col,
        sel_start_row = sel_start_row,
        sel_start_col = sel_start_col,
        sel_end_row = sel_end_row,
        sel_end_col = sel_end_col,
    }
end

---@private
---@param node TSNode
---@return integer?
function M.level(node)
    for child in node:iter_children() do
        local kind = child:type()
        local atx = kind:match('^atx_h(%d)_marker$')
        if atx then
            return tonumber(atx)
        elseif kind == 'setext_h1_underline' then
            return 1
        elseif kind == 'setext_h2_underline' then
            return 2
        end
    end
    return nil
end

---Prefer the inline title. Setext stores that inline under a paragraph.
---@private
---@param node TSNode
---@return TSNode?
function M.title(node)
    local content = node:field('heading_content')[1]
    if not content then
        return nil
    end
    if content:type() == 'inline' then
        return content
    end
    for child in content:iter_children() do
        if child:type() == 'inline' then
            return child
        end
    end
    return content
end

---@private
---@param buf integer
---@param headings render.md.lsp.Heading[]
---@param root TSNode
---@param encoding render.md.lsp.Encoding
---@return lsp.DocumentSymbol[]
function M.hierarchy(buf, headings, root, encoding)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local _, _, doc_end_row, doc_end_col = root:range()

    ---@param row integer
    ---@param col integer
    ---@return lsp.Position
    local function position(row, col)
        return {
            line = row,
            character = M.character(lines[row + 1] or '', col, encoding),
        }
    end

    ---@param start_row integer
    ---@param start_col integer
    ---@param end_row integer
    ---@param end_col integer
    ---@return lsp.Range
    local function range(start_row, start_col, end_row, end_col)
        return {
            start = position(start_row, start_col),
            ['end'] = position(end_row, end_col),
        }
    end

    local ends = {} ---@type integer[][]
    for i, heading in ipairs(headings) do
        local end_row, end_col = doc_end_row, doc_end_col
        for j = i + 1, #headings do
            local next_heading = headings[j]
            if next_heading.level <= heading.level then
                end_row = next_heading.start_row
                end_col = next_heading.start_col
                break
            end
        end
        ends[i] = { end_row, end_col }
    end

    local roots = {} ---@type lsp.DocumentSymbol[]
    local stack = {} ---@type { level: integer, symbol: lsp.DocumentSymbol }[]
    for i, heading in ipairs(headings) do
        ---@type lsp.DocumentSymbol
        local symbol = {
            name = heading.name,
            kind = vim.lsp.protocol.SymbolKind.String,
            range = range(
                heading.start_row,
                heading.start_col,
                ends[i][1],
                ends[i][2]
            ),
            selectionRange = range(
                heading.sel_start_row,
                heading.sel_start_col,
                heading.sel_end_row,
                heading.sel_end_col
            ),
        }
        while #stack > 0 and stack[#stack].level >= heading.level do
            table.remove(stack)
        end
        local parent = stack[#stack]
        if parent then
            local children = parent.symbol.children
            if not children then
                children = {}
                parent.symbol.children = children
            end
            children[#children + 1] = symbol
        else
            roots[#roots + 1] = symbol
        end
        stack[#stack + 1] = { level = heading.level, symbol = symbol }
    end
    return roots
end

---@private
---@param line string
---@param col integer byte index, 0-based
---@param encoding render.md.lsp.Encoding
---@return integer
function M.character(line, col, encoding)
    if col <= 0 then
        return 0
    end
    if col > #line then
        col = #line
    end
    if encoding == 'utf-8' then
        return col
    end
    if compat.has_11 then
        return vim.str_utfindex(line, encoding, col)
    end
    local col32, col16 = vim.str_utfindex(line, col)
    if encoding == 'utf-32' then
        return col32
    end
    return col16
end

return M
