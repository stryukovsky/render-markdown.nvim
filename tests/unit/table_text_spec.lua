---@module 'luassert'

local table_text = require('render-markdown.lib.table_text')

---@param line string
---@return integer[]
local function bars(line)
    local pos = {}
    local col = 0
    for _, ch in ipairs(vim.fn.split(line, [[\zs]])) do
        if
            ch == '│'
            or ch == '┌'
            or ch == '┬'
            or ch == '┐'
            or ch == '├'
            or ch == '┼'
            or ch == '┤'
            or ch == '└'
            or ch == '┴'
            or ch == '┘'
        then
            pos[#pos + 1] = col
        end
        col = col + vim.api.nvim_strwidth(ch)
    end
    return pos
end

---@param lines string[]
---@param total_document_columns_size integer
local function assert_grid(lines, total_document_columns_size)
    local columns = bars(lines[1])
    for _, line in ipairs(lines) do
        assert.equal(total_document_columns_size, vim.api.nvim_strwidth(line))
        assert.same(columns, bars(line))
    end
end

describe('table text', function()
    it('splits the line across columns by widest-cell proportion', function()
        local rendered = assert(table_text.block({
            '| A | B |',
            '| --- | --- |',
            '| a | b |',
            '| c | d |',
        }, 20))
        assert.same({
            '┌─────────┬────────┐',
            '│ A       │ B      │',
            '├─────────┼────────┤',
            '│ a       │ b      │',
            '├─────────┼────────┤',
            '│ c       │ d      │',
            '└─────────┴────────┘',
        }, rendered.lines)
        assert.same({
            'head',
            'head',
            'head',
            'row',
            'row',
            'row',
            'row',
        }, rendered.kinds)
        assert_grid(rendered.lines, 20)
    end)

    it('wraps a cell that is wider than its share of the line', function()
        local rendered = assert(table_text.block({
            '| Name | Notes |',
            '| --- | --- |',
            '| alpha | one two three four |',
        }, 24))
        local lines = rendered.lines
        assert_grid(lines, 24)
        local text = table.concat(lines, '\n')
        assert.truthy(text:find('alpha', 1, true))
        assert.truthy(text:find('four', 1, true))
        assert.is_true(#lines >= 5)
        assert.equal('head', rendered.kinds[1])
        assert.equal('row', rendered.kinds[#rendered.kinds])
    end)

    it(
        'marks right alignment on the separator and pads the cell with spaces',
        function()
            local rendered = assert(table_text.block({
                '| Item | Num |',
                '| --- | ---: |',
                '| a | 5 |',
            }, 24))
            assert.same({
                '┌────────────┬─────────┐',
                '│ Item       │ Num     │',
                '├────────────┼────────━┤',
                '│ a          │ 5       │',
                '└────────────┴─────────┘',
            }, rendered.lines)
            assert.equal('head', rendered.kinds[3])
            assert_grid(rendered.lines, 24)
        end
    )

    it('keeps a wrapped word intact and pads the shorter lines', function()
        local notes = string.rep('token ', 40)
        local rendered = assert(table_text.block({
            '| Role | Notes |',
            '| --- | --- |',
            '| Роль в контуре | ' .. notes .. ' |',
        }, 40))
        local text = table.concat(rendered.lines, '\n')
        assert.truthy(text:find('контуре', 1, true))
        assert_grid(rendered.lines, 40)
        local short_line = nil
        for _, line in ipairs(rendered.lines) do
            if line:find(' в ', 1, true) or line:find('│ в', 1, true) then
                short_line = line
            end
        end
        assert.not_nil(short_line)
        assert.equal(
            vim.api.nvim_strwidth(rendered.lines[1]),
            vim.api.nvim_strwidth(short_line)
        )
    end)

    it('keeps a quoted table inside the line width', function()
        local rendered = assert(table_text.block({
            '> | A | B |',
            '> | --- | --- |',
            '> | a | b |',
        }, 20))
        assert_grid(rendered.lines, 20)
        assert.equal('> ', rendered.lines[1]:sub(1, 2))
    end)
end)
