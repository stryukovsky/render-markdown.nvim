local str = require('render-markdown.lib.str')

---@class render.md.Wrap
local M = {}

---Source row uses the low 26 bits, preview row the next 26 bits.
---Both fit in the exact integer range of a Lua number.
local ROW_BITS = 26
local ROW_MASK = 2 ^ ROW_BITS - 1
local ROW_SPAN = 2 ^ ROW_BITS

---Leading blockquote markers, including the whitespace that follows them.
---@param line string
---@return string
local function quote_prefix(line)
    local i = 1
    local n = #line
    while i <= n and line:sub(i, i):match('%s') do
        i = i + 1
    end
    local saw = false
    while i <= n and line:sub(i, i) == '>' do
        saw = true
        i = i + 1
        while i <= n and line:sub(i, i):match('%s') do
            i = i + 1
        end
    end
    if not saw then
        return ''
    end
    return line:sub(1, i - 1)
end

---@param line string
---@param width integer
---@return string[]
local function hard(line, width)
    local result = {} ---@type string[]
    local total = str.width(line)
    local col = 1
    while col <= total do
        local piece = str.sub(line, col, math.min(total, col + width - 1))
        if piece == '' then
            break
        end
        result[#result + 1] = piece
        col = col + str.width(piece)
    end
    if #result == 0 then
        result[1] = line
    end
    return result
end

---Wrap one line on word boundaries. Continuation lines keep quote markers and
---align under the text of a list item.
---@param line string
---@param width integer
---@return string[]
function M.line(line, width)
    if width < 1 or str.width(line) <= width then
        return { line }
    end

    local quote = quote_prefix(line)
    local rest = line:sub(#quote + 1)
    local indent, marker = rest:match('^(%s*)(%-%s+%[[ xX%-]%s*%]%s+)')
    if not marker then
        indent, marker = rest:match('^(%s*)([%-%+%*]%s+)')
    end
    if not marker then
        indent, marker = rest:match('^(%s*)(%d+[%.%)]%s+)')
    end
    indent = indent or ''
    marker = marker or ''

    local head = #quote + #indent + #marker
    local body = line:sub(head + 1)
    local first_prefix = line:sub(1, head)
    local next_prefix = quote .. indent .. str.pad(str.width(marker))
    local first_budget = width - str.width(first_prefix)
    local next_budget = width - str.width(next_prefix)
    if first_budget < 1 or next_budget < 1 then
        return hard(line, width)
    end

    local words = {} ---@type string[]
    for word in body:gmatch('%S+') do
        words[#words + 1] = word
    end
    if #words == 0 then
        return hard(line, width)
    end

    local result = {} ---@type string[]
    local current = ''
    local budget = first_budget
    local prefix = first_prefix

    local function flush()
        result[#result + 1] = prefix .. current
        current = ''
        prefix = next_prefix
        budget = next_budget
    end

    ---@param word string
    local function place(word)
        local function room()
            if current == '' then
                return budget
            end
            return budget - str.width(current) - 1
        end
        if str.width(word) <= room() then
            current = current == '' and word or (current .. ' ' .. word)
            return
        end
        if current ~= '' then
            flush()
        end
        if str.width(word) <= budget then
            current = word
            return
        end
        local total = str.width(word)
        local col = 1
        while col <= total do
            local piece = str.sub(word, col, col + budget - 1)
            if piece == '' then
                break
            end
            if current ~= '' then
                flush()
            end
            current = piece
            col = col + str.width(piece)
            if col <= total then
                flush()
            end
        end
    end

    for _, word in ipairs(words) do
        place(word)
    end
    if current ~= '' then
        result[#result + 1] = prefix .. current
    end
    return result
end

---Wrap every line that is not marked protected. `protected` is keyed by
---0-based source row. The returned map sends each source row to the first
---wrapped row, also 0-based.
---@param lines string[]
---@param protected table<integer, boolean>
---@param width integer
---@return string[], table<integer, integer>
function M.lines(lines, protected, width)
    local out = {} ---@type string[]
    local map = {} ---@type table<integer, integer>
    for i, line in ipairs(lines) do
        map[i - 1] = #out
        local chunk = protected[i - 1] and { line } or M.line(line, width)
        for _, item in ipairs(chunk) do
            out[#out + 1] = item
        end
    end
    if #out == 0 then
        out[1] = ''
    end
    return out, map
end

---@class render.md.wrap.Piece
---@field text string
---Low 26 bits are the source row, the next 26 bits are the preview row.
---@field rows integer

---@param source_row integer
---@param preview_row integer
---@return integer
function M.pack(source_row, preview_row)
    local source = bit.band(source_row, ROW_MASK)
    local preview = bit.band(preview_row, ROW_MASK)
    return source + preview * ROW_SPAN
end

---@param rows integer
---@return integer source_row
---@return integer preview_row
function M.unpack(rows)
    return bit.band(rows, ROW_MASK), math.floor(rows / ROW_SPAN)
end

return M
