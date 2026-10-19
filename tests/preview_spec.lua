---@module 'luassert'

local util = require('tests.util')

describe('preview', function()
    it('opens a listed buffer wrapped at 90 columns', function()
        local cell = string.rep('abcdefg ', 12)
        local prose = string.rep('alpha ', 20)
        util.setup.text({
            '# Title',
            '',
            prose,
            '',
            '| Left | Right |',
            '| --- | --- |',
            '| ' .. cell .. ' | ' .. cell .. ' |',
        })

        vim.o.columns = 120
        local src = vim.api.nvim_get_current_buf()
        local windows = #vim.api.nvim_list_wins()
        require('render-markdown.core.preview').open()
        local dst = vim.api.nvim_get_current_buf()

        assert.not_equal(src, dst)
        assert.equal(windows, #vim.api.nvim_list_wins())
        assert.is_true(vim.bo[dst].buflisted)
        assert.equal(src, require('render-markdown.core.preview').get(dst))

        local lines = vim.api.nvim_buf_get_lines(dst, 0, -1, false)
        local table_width = nil ---@type integer?
        for _, line in ipairs(lines) do
            local width = vim.api.nvim_strwidth(line)
            local head = line:sub(1, 3)
            local rule = head == '┌'
                or head == '│'
                or head == '├'
                or head == '└'
            if rule then
                table_width = table_width or width
                assert.equal(table_width, width)
            else
                assert.is_true(width <= 90, width .. ' ' .. line)
            end
        end
        assert.equal(90, table_width)
        assert.truthy(lines[1] ~= nil)
        assert.truthy(vim.iter(lines):any(function(line)
            return line:find('┌', 1, true) ~= nil
        end))

        local ui = require('render-markdown.core.ui')
        local rendered = vim.wait(1000, function()
            return #vim.api.nvim_buf_get_extmarks(dst, ui.ns, 0, -1, {}) > 0
        end)
        assert.is_true(rendered)

        local details = vim.api.nvim_buf_get_extmarks(dst, ui.ns, 0, -1, {
            details = true,
        })
        local heading = false
        for _, mark in ipairs(details) do
            local info = mark[4]
            if info.hl_group == 'RenderMarkdownH1Bg' then
                heading = true
            end
            for _, virt_line in ipairs(info.virt_lines or {}) do
                local text = ''
                for _, chunk in ipairs(virt_line) do
                    text = text .. chunk[1]
                end
                assert.is_nil(text:find('│', 1, true))
                assert.is_nil(text:find('┌', 1, true))
            end
        end
        assert.is_true(heading)

        local preview = require('render-markdown.core.preview')
        local table_marks =
            vim.api.nvim_buf_get_extmarks(dst, preview.ns, 0, -1, {
                details = true,
            })
        local table_hl = false
        for _, mark in ipairs(table_marks) do
            local group = mark[4].hl_group
            if
                group == 'RenderMarkdownTableHead'
                or group == 'RenderMarkdownTableRow'
            then
                table_hl = true
            end
        end
        assert.is_true(table_hl)

        require('render-markdown.core.preview').close(src)
        assert.equal(src, vim.api.nvim_get_current_buf())
    end)

    it('follows the cursor between the source and the preview', function()
        local prose = string.rep('alpha ', 40)
        util.setup.text({ prose, '', 'tail' })
        local src = vim.api.nvim_get_current_buf()
        local preview_win = vim.api.nvim_get_current_win()
        vim.cmd('split')
        local source_win = vim.api.nvim_get_current_win()
        vim.api.nvim_set_current_win(preview_win)
        vim.api.nvim_win_set_cursor(preview_win, { 1, 0 })

        local preview = require('render-markdown.core.preview')
        preview.open()
        assert.equal(src, vim.api.nvim_win_get_buf(source_win))
        local dst = vim.api.nvim_win_get_buf(preview_win)
        assert.not_equal(src, dst)

        vim.api.nvim_set_current_win(source_win)
        vim.api.nvim_win_set_cursor(source_win, { 3, 0 })
        -- Headless Neovim does not emit these events on its own.
        vim.api.nvim_exec_autocmds('CursorMoved', { buffer = src })
        local followed = vim.api.nvim_win_get_cursor(preview_win)
        assert.is_true(followed[1] > 1)
        assert.equal(0, followed[2])

        vim.api.nvim_set_current_win(preview_win)
        vim.api.nvim_win_set_cursor(preview_win, { 1, 0 })
        vim.api.nvim_exec_autocmds('CursorMoved', { buffer = dst })
        assert.same({ 1, 0 }, vim.api.nvim_win_get_cursor(source_win))

        vim.api.nvim_set_current_win(source_win)
        vim.api.nvim_buf_set_lines(src, 0, -1, false, { 'short', '', 'tail' })
        vim.api.nvim_exec_autocmds('TextChanged', { buffer = src })
        assert.same(
            { 'short', '', 'tail' },
            vim.api.nvim_buf_get_lines(dst, 0, -1, false)
        )

        preview.close(src)
        vim.cmd('only')
    end)

    it('indexes headings in the preview buffer', function()
        local cell = string.rep('word ', 30)
        util.setup.text({
            '# First',
            '',
            '| a | b |',
            '| --- | --- |',
            '| ' .. cell .. ' | ' .. cell .. ' |',
            '',
            '# Second',
        }, {
            completions = { lsp = { enabled = true } },
        })
        local src = vim.api.nvim_get_current_buf()
        local preview = require('render-markdown.core.preview')
        preview.open()
        local dst = vim.api.nvim_get_current_buf()

        assert.equal('', vim.bo[dst].buftype)
        assert.not_equal(
            vim.api.nvim_buf_get_name(src),
            vim.api.nvim_buf_get_name(dst)
        )
        assert.not_equal('', vim.api.nvim_buf_get_name(dst))

        local lsp = require('render-markdown.integ.lsp')
        ---@param buf integer
        ---@param name string
        ---@return integer?
        local function heading_line(buf, name)
            for _, symbol in ipairs(lsp.symbols(buf, 'utf-8') or {}) do
                if symbol.name == name then
                    return symbol.selectionRange.start.line
                end
            end
        end
        local src_second = heading_line(src, 'Second')
        local dst_second = heading_line(dst, 'Second')
        assert.equal(0, heading_line(dst, 'First'))
        assert.is_true(dst_second > src_second)

        local attached = vim.wait(1000, function()
            local clients = vim.lsp.get_clients({
                bufnr = dst,
                name = 'render-markdown',
            })
            return #clients == 1
        end)
        assert.is_true(attached)

        preview.close(src)
    end)
end)
