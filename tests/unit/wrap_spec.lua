---@module 'luassert'

local wrap = require('render-markdown.lib.wrap')

describe('wrap', function()
    it('leaves short lines', function()
        assert.same({ 'hello' }, wrap.line('hello', 90))
    end)

    it('breaks on words', function()
        local line = 'one two three four'
        assert.same({ 'one two', 'three four' }, wrap.line(line, 11))
    end)

    it('splits a word that exceeds the width', function()
        assert.same({ 'abcdef', 'ghij' }, wrap.line('abcdefghij', 6))
    end)

    it('keeps list marker on the first line only', function()
        local line = '- alpha beta gamma'
        assert.same({ '- alpha', '  beta', '  gamma' }, wrap.line(line, 8))
    end)

    it('repeats quote markers', function()
        local line = '> alpha beta gamma'
        assert.same({ '> alpha', '> beta', '> gamma' }, wrap.line(line, 8))
    end)

    it('stays within the requested width', function()
        local line = string.rep('alpha ', 20)
        for _, wrapped in ipairs(wrap.line(line, 90)) do
            assert.is_true(
                vim.fn.strdisplaywidth(wrapped) <= 90,
                vim.fn.strdisplaywidth(wrapped) .. ' ' .. wrapped
            )
        end
    end)

    it('skips protected rows', function()
        local lines = {
            'alpha beta gamma',
            '| very long table row that stays intact |',
        }
        local wrapped = wrap.lines(lines, { [1] = true }, 10)
        assert.same({
            'alpha beta',
            'gamma',
            '| very long table row that stays intact |',
        }, wrapped)
    end)
end)
