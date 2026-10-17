local wrap = require('render-markdown.lib.wrap')

---@class render.md.sync.paragraph.Row
---@field source_row integer
---@field pieces render.md.wrap.Piece[]

---@class render.md.sync.Paragraph
---@field kind 'paragraph'
---@field source_start integer 0-based, first source line
---@field source_end integer 0-based, exclusive
---@field preview_start integer 0-based, first preview line
---@field preview_end integer 0-based, exclusive
---@field source_count integer N source lines
---@field preview_count integer M preview lines after wrapping
---@field source_lines string[]
---@field preview_lines string[]
---source row -> first preview row produced by that source line
---@field line_map table<integer, integer>
---@field rows render.md.sync.paragraph.Row[]

---@class render.md.sync.ParagraphModule
local M = {}

---Wrap a run of prose. Each source line becomes one or more preview lines,
---and the paragraph remembers that N lines turned into M lines.
---@param source_lines string[]
---@param source_start integer
---@param preview_start integer
---@param width integer
---@return render.md.sync.Paragraph
function M.render(source_lines, source_start, preview_start, width)
    local rows = {} ---@type render.md.sync.paragraph.Row[]
    local preview_lines = {} ---@type string[]
    local line_map = {} ---@type table<integer, integer>
    for i, line in ipairs(source_lines) do
        local source_row = source_start + i - 1
        local pieces = {} ---@type render.md.wrap.Piece[]
        line_map[source_row] = preview_start + #preview_lines
        for _, text in ipairs(wrap.line(line, width)) do
            local preview_row = preview_start + #preview_lines
            pieces[#pieces + 1] = {
                text = text,
                rows = wrap.pack(source_row, preview_row),
            }
            preview_lines[#preview_lines + 1] = text
        end
        rows[#rows + 1] = { source_row = source_row, pieces = pieces }
    end
    ---@type render.md.sync.Paragraph
    return {
        kind = 'paragraph',
        source_start = source_start,
        source_end = source_start + #source_lines,
        preview_start = preview_start,
        preview_end = preview_start + #preview_lines,
        source_count = #source_lines,
        preview_count = #preview_lines,
        source_lines = source_lines,
        preview_lines = preview_lines,
        line_map = line_map,
        rows = rows,
    }
end

---A source line maps to the first preview line it wrapped into.
---@param block render.md.sync.Paragraph
---@param row integer
---@return integer, integer
function M.preview_pos(block, row)
    local state = block.rows[row - block.source_start + 1]
    if not state or #state.pieces == 0 then
        return block.preview_start, 0
    end
    local _, preview_row = wrap.unpack(state.pieces[1].rows)
    return preview_row, 0
end

---Any wrapped preview line maps back to its source line.
---@param block render.md.sync.Paragraph
---@param preview_row integer
---@return integer, integer
function M.source_pos(block, preview_row)
    for _, state in ipairs(block.rows) do
        for _, item in ipairs(state.pieces) do
            local source_row, item_row = wrap.unpack(item.rows)
            if item_row == preview_row then
                return source_row, 0
            end
        end
    end
    return block.source_start, 0
end

return M
