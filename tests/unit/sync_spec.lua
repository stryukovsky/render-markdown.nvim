---@module 'luassert'

local sync = require('render-markdown.sync')
local table_text = require('render-markdown.lib.table_text')

describe('sync', function()
    it(
        'remembers that one source line wrapped into several preview lines',
        function()
            local line = 'alpha beta gamma delta'
            local doc = sync.build({ line }, {}, 10)
            local block = doc.blocks[1]
            assert.equal('paragraph', block.kind)
            assert.equal(0, block.source_start)
            assert.equal(1, block.source_count)
            assert.is_true(block.preview_count > 1)
            assert.equal(block.preview_count, #block.preview_lines)
            assert.equal(0, block.line_map[0])
            assert.same(doc.lines, block.preview_lines)
        end
    )

    it('maps a source line onto the preview lines it wrapped into', function()
        local wrap = require('render-markdown.lib.wrap')
        local line = 'alpha beta gamma delta epsilon'
        local doc = sync.build({ line }, {}, 10)
        local block = doc.blocks[1]
        for col = 0, #line do
            local preview_row, preview_col = doc:to_preview(0, col)
            assert.equal(block.line_map[0], preview_row)
            assert.equal(0, preview_col)
        end
        for _, piece in ipairs(block.rows[1].pieces) do
            local source_row, preview_row = wrap.unpack(piece.rows)
            local back_row, back_col = doc:to_source(preview_row, 3)
            assert.equal(0, source_row)
            assert.equal(source_row, back_row)
            assert.equal(0, back_col)
        end
        assert.is_true(#block.rows[1].pieces > 1)
    end)

    it(
        'maps each source line of a paragraph onto its own preview run',
        function()
            local lines = {
                'alpha beta gamma',
                'delta epsilon zeta',
            }
            local doc = sync.build(lines, {}, 10)
            local block = doc.blocks[1]
            assert.equal('paragraph', block.kind)
            assert.equal(2, block.source_count)
            assert.is_true(block.preview_count > 2)
            local first = block.rows[1]
            local second = block.rows[2]
            local wrap = require('render-markdown.lib.wrap')
            local _, second_preview = wrap.unpack(second.pieces[1].rows)
            assert.equal(#first.pieces, second_preview)
            assert.equal(second_preview, block.line_map[1])

            local preview_row, preview_col = doc:to_preview(1, 0)
            assert.equal(block.line_map[1], preview_row)
            assert.equal(0, preview_col)
            local source_row, source_col = doc:to_source(preview_row, 4)
            assert.equal(1, source_row)
            assert.equal(0, source_col)
        end
    )

    it(
        'keeps later paragraphs aligned past a blank line and a table',
        function()
            local lines = {
                'alpha beta gamma',
                '',
                '| A | B |',
                '| --- | --- |',
                '| a | b |',
                '',
                'after table text',
            }
            local rows = { [2] = true, [3] = true, [4] = true }
            local doc = sync.build(lines, rows, 20)
            local kinds = {}
            for _, block in ipairs(doc.blocks) do
                kinds[#kinds + 1] = block.kind
            end
            assert.same({
                'paragraph',
                'blank',
                'table',
                'blank',
                'paragraph',
            }, kinds)

            local wrapped = table_text.lines(lines, rows, 20)
            assert.same(wrapped, doc.lines)

            local tail = doc.blocks[5]
            assert.equal('paragraph', tail.kind)
            assert.equal(6, tail.source_start)
            local preview_row = doc:to_preview(6, 0)
            assert.equal(tail.preview_start, preview_row)
            local source_row = doc:to_source(tail.preview_start, 3)
            assert.equal(6, source_row)
        end
    )
end)
