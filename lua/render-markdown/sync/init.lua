local paragraph = require('render-markdown.sync.paragraph')
local table_text = require('render-markdown.lib.table_text')

---@class render.md.sync.Gap
---@field kind 'blank'
---@field source_start integer
---@field source_end integer
---@field preview_start integer
---@field preview_end integer

---@class render.md.sync.Table
---@field kind 'table'
---@field source_start integer
---@field source_end integer
---@field preview_start integer
---@field preview_end integer

---@alias render.md.sync.Block
---| render.md.sync.Paragraph
---| render.md.sync.Gap
---| render.md.sync.Table

---@class render.md.sync.Document
---@field blocks render.md.sync.Block[]
---@field lines string[]
---@field kinds (string|false)[]
---@field source_lines string[]
---@field source_count integer
local Document = {}
Document.__index = Document

---@class render.md.Sync
local M = {}

---@param line string
---@return boolean
local function is_blank(line)
    return line:match('^%s*$') ~= nil
end

---@param row integer
---@param count integer
---@return integer
local function clamp_row(row, count)
    if count < 1 then
        return 0
    end
    if row < 0 then
        return 0
    end
    if row >= count then
        return count - 1
    end
    return row
end

---@param line? string
---@param col integer
---@return integer
local function clamp_col(line, col)
    line = line or ''
    if col < 0 then
        return 0
    end
    if col > #line then
        return #line
    end
    return col
end

---Placeholder until table sync exists: spread source rows across the rendered
---table, and the other way around. Columns stay at the start of the row.
---@param index integer
---@param from_n integer
---@param to_n integer
---@return integer
local function ratio(index, from_n, to_n)
    if to_n <= 1 or from_n <= 1 then
        return 0
    end
    if index < 0 then
        index = 0
    end
    local offset = math.floor(index * to_n / from_n)
    if offset < 0 then
        return 0
    end
    if offset >= to_n then
        return to_n - 1
    end
    return offset
end

---@param blocks render.md.sync.Block[]
---@param lines string[]
---@param kinds (string|false)[]
---@param block_lines string[]
---@param source_start integer
---@param width integer
---@param opts? render.md.table.text.Opts
local function append_table(
    blocks,
    lines,
    kinds,
    block_lines,
    source_start,
    width,
    opts
)
    local rendered = table_text.block(block_lines, width, opts)
    if not rendered or #rendered.lines == 0 then
        local prose = paragraph.render(block_lines, source_start, #lines, width)
        for _, line in ipairs(prose.preview_lines) do
            lines[#lines + 1] = line
            kinds[#kinds + 1] = false
        end
        blocks[#blocks + 1] = prose
        return
    end
    local preview_start = #lines
    for i, line in ipairs(rendered.lines) do
        lines[#lines + 1] = line
        kinds[#kinds + 1] = rendered.kinds[i] or false
    end
    blocks[#blocks + 1] = {
        kind = 'table',
        source_start = source_start,
        source_end = source_start + #block_lines,
        preview_start = preview_start,
        preview_end = #lines,
    }
end

---Build the document. Paragraphs are the only block with a column mapping.
---Blank lines separate them. Tables are emitted with the existing renderer so
---later paragraphs stay aligned; their cursor mapping is filled in later.
---@param src_lines string[]
---@param table_rows table<integer, boolean>
---@param width integer
---@param opts? render.md.table.text.Opts
---@return render.md.sync.Document
function M.build(src_lines, table_rows, width, opts)
    local blocks = {} ---@type render.md.sync.Block[]
    local lines = {} ---@type string[]
    local kinds = {} ---@type (string|false)[]
    local index = 1
    while index <= #src_lines do
        if table_rows[index - 1] then
            local source_start = index - 1
            local block_lines = {} ---@type string[]
            while index <= #src_lines and table_rows[index - 1] do
                block_lines[#block_lines + 1] = src_lines[index]
                index = index + 1
            end
            append_table(
                blocks,
                lines,
                kinds,
                block_lines,
                source_start,
                width,
                opts
            )
        elseif is_blank(src_lines[index]) then
            local source_start = index - 1
            local preview_start = #lines
            while
                index <= #src_lines
                and is_blank(src_lines[index])
                and not table_rows[index - 1]
            do
                lines[#lines + 1] = src_lines[index]
                kinds[#kinds + 1] = false
                index = index + 1
            end
            blocks[#blocks + 1] = {
                kind = 'blank',
                source_start = source_start,
                source_end = index - 1,
                preview_start = preview_start,
                preview_end = #lines,
            }
        else
            local source_start = index - 1
            local block_lines = {} ---@type string[]
            while
                index <= #src_lines
                and not table_rows[index - 1]
                and not is_blank(src_lines[index])
            do
                block_lines[#block_lines + 1] = src_lines[index]
                index = index + 1
            end
            local prose =
                paragraph.render(block_lines, source_start, #lines, width)
            for _, line in ipairs(prose.preview_lines) do
                lines[#lines + 1] = line
                kinds[#kinds + 1] = false
            end
            blocks[#blocks + 1] = prose
        end
    end
    if #lines == 0 then
        lines[1] = ''
        kinds[1] = false
        blocks[1] = {
            kind = 'blank',
            source_start = 0,
            source_end = 0,
            preview_start = 0,
            preview_end = 1,
        }
    end
    return setmetatable({
        blocks = blocks,
        lines = lines,
        kinds = kinds,
        source_lines = src_lines,
        source_count = #src_lines,
    }, Document)
end

---@param blocks render.md.sync.Block[]
---@param row integer
---@param start_key 'source_start'|'preview_start'
---@param end_key 'source_end'|'preview_end'
---@return render.md.sync.Block?
local function block_at(blocks, row, start_key, end_key)
    for _, block in ipairs(blocks) do
        if row >= block[start_key] and row < block[end_key] then
            return block
        end
    end
    return blocks[#blocks]
end

---@param self render.md.sync.Document
---@param row integer 0-based
---@param col integer 0-based byte
---@return integer, integer
function Document:to_preview(row, col)
    if #self.lines == 0 then
        return 0, 0
    end
    row = clamp_row(row, math.max(self.source_count, 1))
    local block = block_at(self.blocks, row, 'source_start', 'source_end')
    local preview_row, preview_col = 0, 0
    if block and block.kind == 'paragraph' then
        preview_row, preview_col = paragraph.preview_pos(block, row)
    elseif block and block.kind == 'blank' then
        preview_row = block.preview_start + (row - block.source_start)
        preview_col = col
    elseif block and block.kind == 'table' then
        local source_n = block.source_end - block.source_start
        local preview_n = block.preview_end - block.preview_start
        local offset = ratio(row - block.source_start, source_n, preview_n)
        preview_row = block.preview_start + offset
        preview_col = 0
    end
    preview_row = clamp_row(preview_row, #self.lines)
    preview_col = clamp_col(self.lines[preview_row + 1], preview_col)
    return preview_row, preview_col
end

---@param self render.md.sync.Document
---@param row integer 0-based
---@param col integer 0-based byte
---@return integer, integer
function Document:to_source(row, col)
    if self.source_count < 1 then
        return 0, 0
    end
    row = clamp_row(row, #self.lines)
    local block = block_at(self.blocks, row, 'preview_start', 'preview_end')
    local source_row, source_col = 0, 0
    if block and block.kind == 'paragraph' then
        source_row, source_col = paragraph.source_pos(block, row)
    elseif block and block.kind == 'blank' then
        source_row = block.source_start + (row - block.preview_start)
        source_col = col
    elseif block and block.kind == 'table' then
        local source_n = block.source_end - block.source_start
        local preview_n = block.preview_end - block.preview_start
        local offset = ratio(row - block.preview_start, preview_n, source_n)
        source_row = block.source_start + offset
        source_col = 0
    end
    source_row = clamp_row(source_row, self.source_count)
    source_col = clamp_col(self.source_lines[source_row + 1], source_col)
    return source_row, source_col
end

return M
