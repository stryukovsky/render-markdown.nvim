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
end)
