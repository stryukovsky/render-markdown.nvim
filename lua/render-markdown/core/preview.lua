local env = require('render-markdown.lib.env')
local manager = require('render-markdown.core.manager')
local state = require('render-markdown.state')
local table_text = require('render-markdown.lib.table_text')

---@class render.md.Preview
local M = {}

---Display columns available for one preview line.
---Prose is hard-wrapped to this width. Tables use the same width: separators
---and padding are reserved first, then the rest is split across columns in
---proportion to the widest cell in each column.
M.columns = 90

---@private
M.ns = vim.api.nvim_create_namespace('render-markdown.preview.table')

---@private
M.group = vim.api.nvim_create_augroup('RenderMarkdownPreview', {})

---source buffer -> preview buffer
---@private
---@type table<integer, integer>
M.buffers = {}

---source buffer -> enabled flag to restore when the preview closes
---@private
---@type table<integer, boolean>
M.restore = {}

---source buffer -> source row to first preview row
---@private
---@type table<integer, table<integer, integer>>
M.maps = {}

---@param buf integer
---@return integer?
function M.get(buf)
    for src, dst in pairs(M.buffers) do
        if buf == dst then
            return src
        end
    end
    return nil
end

---@param src_buf? integer
function M.open(src_buf)
    src_buf = src_buf or env.buf.current()
    local preview_src = M.get(src_buf)
    if preview_src then
        M.close(preview_src)
        return
    end
    local existing = M.buffers[src_buf]
    if existing and not vim.api.nvim_buf_is_valid(existing) then
        M.buffers[src_buf] = nil
        existing = nil
    end
    if existing then
        local win = env.win.current()
        vim.api.nvim_win_set_buf(win, existing)
        M.window(existing)
        M.refresh(src_buf, existing)
        return
    end
    if not manager.attached(src_buf) then
        return
    end

    local src_win = env.buf.win(src_buf)
    if not env.win.valid(src_win) then
        src_win = env.win.current()
    end
    local cursor = vim.api.nvim_win_get_cursor(src_win)

    M.restore[src_buf] = state.get(src_buf).enabled
    manager.set_buf(src_buf, false)

    local dst_buf = vim.api.nvim_create_buf(true, true)
    M.buffers[src_buf] = dst_buf

    local src_name = vim.api.nvim_buf_get_name(src_buf)
    local label = src_name ~= '' and src_name or tostring(src_buf)
    pcall(vim.api.nvim_buf_set_name, dst_buf, 'preview://' .. label)

    env.buf.set(dst_buf, 'buflisted', true)
    env.buf.set(dst_buf, 'bufhidden', 'hide')
    env.buf.set(dst_buf, 'buftype', 'nofile')
    env.buf.set(dst_buf, 'swapfile', false)
    M.refresh(src_buf, dst_buf)
    env.buf.set(dst_buf, 'modifiable', false)

    -- Show the buffer before FileType attaches. Treesitter opens a temporary
    -- window while starting the parser, and the first render must target the
    -- real window rather than that one.
    vim.api.nvim_win_set_buf(src_win, dst_buf)
    M.window(dst_buf)
    env.buf.set(dst_buf, 'filetype', env.buf.get(src_buf, 'filetype'))
    local row = (M.maps[src_buf] or {})[cursor[1] - 1] or 0
    pcall(vim.api.nvim_win_set_cursor, src_win, { row + 1, 0 })

    vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
        group = M.group,
        buffer = src_buf,
        callback = function()
            local dst = M.buffers[src_buf]
            if
                dst
                and vim.api.nvim_buf_is_valid(src_buf)
                and vim.api.nvim_buf_is_valid(dst)
            then
                M.refresh(src_buf, dst)
            end
        end,
    })

    vim.api.nvim_create_autocmd('BufWinEnter', {
        group = M.group,
        buffer = dst_buf,
        callback = function(args)
            M.window(args.buf)
        end,
    })

    vim.api.nvim_create_autocmd('BufWipeout', {
        group = M.group,
        buffer = dst_buf,
        once = true,
        callback = function()
            if not M.buffers[src_buf] then
                return
            end
            M.buffers[src_buf] = nil
            M.maps[src_buf] = nil
            local restore = M.restore[src_buf]
            M.restore[src_buf] = nil
            vim.api.nvim_clear_autocmds({ group = M.group, buffer = src_buf })
            if restore ~= nil and vim.api.nvim_buf_is_valid(src_buf) then
                manager.set_buf(src_buf, restore)
            end
        end,
    })

    vim.api.nvim_create_autocmd('BufWipeout', {
        group = M.group,
        buffer = src_buf,
        callback = function()
            local dst = M.buffers[src_buf]
            M.buffers[src_buf] = nil
            M.maps[src_buf] = nil
            M.restore[src_buf] = nil
            if dst and vim.api.nvim_buf_is_valid(dst) then
                vim.api.nvim_buf_delete(dst, { force = true })
            end
        end,
    })
end

---@param src integer
function M.close(src)
    local dst = M.buffers[src]
    if not dst then
        return
    end
    M.buffers[src] = nil
    M.maps[src] = nil
    local restore = M.restore[src]
    M.restore[src] = nil
    vim.api.nvim_clear_autocmds({ group = M.group, buffer = src })
    if vim.api.nvim_buf_is_valid(dst) then
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_get_buf(win) == dst then
                pcall(vim.api.nvim_win_set_buf, win, src)
            end
        end
        vim.api.nvim_buf_delete(dst, { force = true })
    end
    if restore ~= nil and vim.api.nvim_buf_is_valid(src) then
        manager.set_buf(src, restore)
    end
end

---@private
---@param buf integer
function M.window(buf)
    local win = env.buf.win(buf)
    if not env.win.valid(win) then
        return
    end
    -- Prose is already hard-wrapped. Linebreak would reflow a formatted
    -- table at different spaces on each row, so the borders stop lining up.
    env.win.set(win, 'wrap', true)
    env.win.set(win, 'linebreak', false)
end

---@private
---@param src integer
---@param dst integer
function M.refresh(src, dst)
    local src_lines = vim.api.nvim_buf_get_lines(src, 0, -1, false)
    local config = state.get(src).pipe_table
    local wrapped, map, kinds =
        table_text.lines(src_lines, M.table_rows(src, src_lines), M.columns, {
            padding = config.padding,
            border = config.border,
            indicator = config.alignment_indicator,
        })
    M.maps[src] = map

    local dst_lines = vim.api.nvim_buf_get_lines(dst, 0, -1, false)
    if not vim.deep_equal(dst_lines, wrapped) then
        local view = nil ---@type vim.fn.winsaveview.ret?
        local win = env.buf.win(dst)
        if env.win.valid(win) and env.win.buf(win) == dst then
            view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
        end

        env.buf.set(dst, 'modifiable', true)
        vim.api.nvim_buf_set_lines(dst, 0, -1, false, wrapped)
        env.buf.set(dst, 'modifiable', false)
        env.buf.set(dst, 'modified', false)

        if view and env.win.valid(win) then
            pcall(vim.api.nvim_win_call, win, function()
                vim.fn.winrestview(view)
            end)
        end
    end
    M.highlight(dst, kinds)
end

---@private
---@param buf integer
---@param kinds (string|false)[]
function M.highlight(buf, kinds)
    vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for i, kind in ipairs(kinds) do
        local hl = kind == 'head' and 'RenderMarkdownTableHead'
            or kind == 'row' and 'RenderMarkdownTableRow'
        local line = lines[i]
        if hl and line and line ~= '' then
            vim.api.nvim_buf_set_extmark(buf, M.ns, i - 1, 0, {
                end_col = #line,
                hl_group = hl,
                hl_mode = 'combine',
            })
        end
    end
end

---Pipe-table rows, keyed by 0-based source row. Those rows are replaced with
---pretty-printed text instead of being wrapped as prose.
---@private
---@param buf integer
---@param lines string[]
---@return table<integer, boolean>
function M.table_rows(buf, lines)
    local protected = {} ---@type table<integer, boolean>
    local found = false
    local ok, parser = pcall(vim.treesitter.get_parser, buf, 'markdown')
    if ok and parser then
        local parsed, trees = pcall(function()
            return parser:parse()
        end)
        local tree = parsed and trees and trees[1]
        if tree then
            local query_ok, query = pcall(
                vim.treesitter.query.parse,
                'markdown',
                '(pipe_table) @table'
            )
            if query_ok and query then
                for _, node in query:iter_captures(tree:root(), buf, 0, -1) do
                    found = true
                    local start_row, _, end_row, end_col = node:range()
                    if end_col == 0 and end_row > start_row then
                        end_row = end_row - 1
                    end
                    for row = start_row, end_row do
                        protected[row] = true
                    end
                end
            end
        end
    end
    if found then
        return protected
    end

    local delim = {} ---@type table<integer, boolean>
    for i, line in ipairs(lines) do
        if
            line:find('|', 1, true)
            and line:find('%-', 1, true)
            and line:match('^%s*|?%s*:?%-')
        then
            delim[i] = true
        end
    end
    for i in pairs(delim) do
        local top = i
        while
            top > 1
            and lines[top - 1]:find('|', 1, true)
            and not lines[top - 1]:match('^%s*$')
        do
            top = top - 1
        end
        local bot = i
        while
            bot < #lines
            and lines[bot + 1]:find('|', 1, true)
            and not lines[bot + 1]:match('^%s*$')
        do
            bot = bot + 1
        end
        for row = top, bot do
            protected[row - 1] = true
        end
    end
    return protected
end

return M
