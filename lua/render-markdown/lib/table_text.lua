local Parser = require('render-markdown.parser.table')
local str = require('render-markdown.lib.str')
local wrap = require('render-markdown.lib.wrap')

---@class render.md.TableText
local M = {}

---@class render.md.table.text.Opts
---@field padding? integer
---@field border? string[]
---@field indicator? string

---@class render.md.table.text.Block
---@field lines string[]
---@field kinds string[]

---@class render.md.table.text.Row
---@field cells string[]
---@field header boolean

local default_border = {
    '┌',
    '┬',
    '┐',
    '├',
    '┼',
    '┤',
    '└',
    '┴',
    '┘',
    '│',
    '─',
}

---@param line string
---@return string
local function row_prefix(line)
    local quote = line:match('^%s*>+%s*') or ''
    local rest = line:sub(#quote + 1)
    local indent = rest:match('^%s*') or ''
    return quote .. indent
end

---@param line string
---@return string[]?
local function split_cells(line)
    if not line:find('|', 1, true) then
        return nil
    end
    local body = line:sub(#row_prefix(line) + 1):gsub('%s+$', '')
    if body:sub(1, 1) == '|' then
        body = body:sub(2)
    end
    if body:sub(-1) == '|' then
        body = body:sub(1, -2)
    end
    -- Pipes inside inline code are part of the cell, as a formatter would keep them.
    local cells = {}
    local current = {}
    local in_code = false
    local i = 1
    while i <= #body do
        local ch = body:sub(i, i)
        if ch == '`' then
            in_code = not in_code
            current[#current + 1] = ch
            i = i + 1
        elseif ch == '|' and not in_code then
            cells[#cells + 1] = vim.trim(table.concat(current))
            current = {}
            i = i + 1
        else
            current[#current + 1] = ch
            i = i + 1
        end
    end
    cells[#cells + 1] = vim.trim(table.concat(current))
    return cells
end

---@param cell string
---@return render.md.table.col.Alignment?
local function alignment_of_delimiter_cell(cell)
    local left = cell:sub(1, 1) == ':'
    local right = cell:sub(-1) == ':'
    local core = cell:gsub(':', '')
    if not core:match('^%-+$') then
        return nil
    end
    if left and right then
        return Parser.Alignment.center
    elseif left then
        return Parser.Alignment.left
    elseif right then
        return Parser.Alignment.right
    end
    return Parser.Alignment.default
end

---Content width left after separators, padding, and the row prefix.
---@param total_document_columns_size integer
---@param table_columns integer
---@param padding integer
---@param chars_count_for_row_prefix integer
---@return integer
local function chars_count_reserved_for_cell_content(
    total_document_columns_size,
    table_columns,
    padding,
    chars_count_for_row_prefix
)
    local chars_count_for_separators = table_columns + 1
    local chars_count_for_paddings = padding * 2 * table_columns
    return total_document_columns_size
        - chars_count_for_row_prefix
        - chars_count_for_paddings
        - chars_count_for_separators
end

---Iteration one: widest cell contents in each column.
---@param rows render.md.table.text.Row[]
---@param table_columns integer
---@return integer[]
local function max_chars_count_in_columns(rows, table_columns)
    local max_chars_count_in_columns = {}
    for column_i = 1, table_columns do
        max_chars_count_in_columns[column_i] = 0
    end
    for _, row in ipairs(rows) do
        for column_i = 1, table_columns do
            local chars_count = str.width(row.cells[column_i] or '')
            if chars_count > max_chars_count_in_columns[column_i] then
                max_chars_count_in_columns[column_i] = chars_count
            end
        end
    end
    return max_chars_count_in_columns
end

---@param chars_count_for_columns integer[]
---@return integer?
local function column_i_with_largest_chars_count(chars_count_for_columns)
    local chosen_column_i = nil
    local largest_chars_count = 1
    for column_i, chars_count_for_column_i in ipairs(chars_count_for_columns) do
        if chars_count_for_column_i > largest_chars_count then
            largest_chars_count = chars_count_for_column_i
            chosen_column_i = column_i
        end
    end
    return chosen_column_i
end

---Proportion:
---max_chars_count_in_column_i / sum_of_max_chars_count_across_columns
---    = chars_count_for_column_i / chars_count_reserved_for_cell_content
---@param max_chars_count_in_columns integer[]
---@param chars_count_reserved_for_cell_content integer
---@return integer[]
local function chars_count_for_columns(
    max_chars_count_in_columns,
    chars_count_reserved_for_cell_content
)
    local table_columns = #max_chars_count_in_columns
    local chars_count_for_columns = {}
    if table_columns == 0 then
        return chars_count_for_columns
    end
    -- Every column needs a place to put at least one character.
    if chars_count_reserved_for_cell_content < table_columns then
        for column_i = 1, table_columns do
            chars_count_for_columns[column_i] = 1
        end
        return chars_count_for_columns
    end

    local weight_of_column = {}
    local sum_of_max_chars_count_across_columns = 0
    for column_i, max_chars_count_in_column_i in
        ipairs(max_chars_count_in_columns)
    do
        weight_of_column[column_i] = max_chars_count_in_column_i
        sum_of_max_chars_count_across_columns = sum_of_max_chars_count_across_columns
            + max_chars_count_in_column_i
    end
    if sum_of_max_chars_count_across_columns == 0 then
        for column_i = 1, table_columns do
            weight_of_column[column_i] = 1
        end
        sum_of_max_chars_count_across_columns = table_columns
    end

    local fractional_remainders = {}
    local assigned_chars_count = 0
    for column_i, max_chars_count_in_column_i in ipairs(weight_of_column) do
        local product = max_chars_count_in_column_i
            * chars_count_reserved_for_cell_content
        local chars_count_for_column_i =
            math.floor(product / sum_of_max_chars_count_across_columns)
        chars_count_for_columns[column_i] = chars_count_for_column_i
        fractional_remainders[column_i] = product
            % sum_of_max_chars_count_across_columns
        assigned_chars_count = assigned_chars_count + chars_count_for_column_i
    end

    local leftover_chars_count = chars_count_reserved_for_cell_content
        - assigned_chars_count
    local order_of_columns = {}
    for column_i = 1, table_columns do
        order_of_columns[column_i] = column_i
    end
    table.sort(order_of_columns, function(left_column_i, right_column_i)
        local left_remainder = fractional_remainders[left_column_i]
        local right_remainder = fractional_remainders[right_column_i]
        if left_remainder ~= right_remainder then
            return left_remainder > right_remainder
        end
        return left_column_i < right_column_i
    end)
    local next_column = 1
    while leftover_chars_count > 0 do
        local column_i = order_of_columns[next_column]
        chars_count_for_columns[column_i] = chars_count_for_columns[column_i]
            + 1
        leftover_chars_count = leftover_chars_count - 1
        next_column = next_column + 1
        if next_column > table_columns then
            next_column = 1
        end
    end

    for column_i = 1, table_columns do
        while chars_count_for_columns[column_i] < 1 do
            local donor_column_i =
                column_i_with_largest_chars_count(chars_count_for_columns)
            if not donor_column_i then
                break
            end
            chars_count_for_columns[donor_column_i] = chars_count_for_columns[donor_column_i]
                - 1
            chars_count_for_columns[column_i] = chars_count_for_columns[column_i]
                + 1
        end
    end

    return chars_count_for_columns
end

---@param cell_contents string
---@return integer
local function longest_word_chars_count(cell_contents)
    local longest_word_chars_count = 0
    for word in cell_contents:gmatch('%S+') do
        local chars_count = str.width(word)
        if chars_count > longest_word_chars_count then
            longest_word_chars_count = chars_count
        end
    end
    return longest_word_chars_count
end

---@param rows render.md.table.text.Row[]
---@param table_columns integer
---@return integer[]
local function longest_word_chars_count_in_columns(rows, table_columns)
    local longest_word_chars_count_in_columns = {}
    for column_i = 1, table_columns do
        longest_word_chars_count_in_columns[column_i] = 1
    end
    for _, row in ipairs(rows) do
        for column_i = 1, table_columns do
            local longest_word_chars_count_in_cell =
                longest_word_chars_count(row.cells[column_i] or '')
            if
                longest_word_chars_count_in_cell
                > longest_word_chars_count_in_columns[column_i]
            then
                longest_word_chars_count_in_columns[column_i] =
                    longest_word_chars_count_in_cell
            end
        end
    end
    return longest_word_chars_count_in_columns
end

---A word that fits in the line keeps its column at least that wide.
---Width is taken from a column that is already wider than its longest word.
---@param chars_count_for_columns integer[]
---@param longest_word_chars_count_in_columns integer[]
---@param chars_count_reserved_for_cell_content integer
---@return integer[]
local function chars_count_for_columns_covering_longest_words(
    chars_count_for_columns,
    longest_word_chars_count_in_columns,
    chars_count_reserved_for_cell_content
)
    local widths = {}
    for column_i, chars_count_for_column_i in ipairs(chars_count_for_columns) do
        widths[column_i] = chars_count_for_column_i
    end

    ---@param longest_word_chars_count integer
    ---@return integer
    local function target_chars_count(longest_word_chars_count)
        if
            longest_word_chars_count < 1
            or longest_word_chars_count
                > chars_count_reserved_for_cell_content
        then
            return 1
        end
        return longest_word_chars_count
    end

    local moves_remaining = math.max(chars_count_reserved_for_cell_content, 0)
    while moves_remaining > 0 do
        moves_remaining = moves_remaining - 1
        local needy_column_i = nil
        local smallest_deficit = nil
        for column_i, chars_count_for_column_i in ipairs(widths) do
            local deficit = target_chars_count(
                longest_word_chars_count_in_columns[column_i]
            ) - chars_count_for_column_i
            if
                deficit > 0
                and (not smallest_deficit or deficit < smallest_deficit)
            then
                smallest_deficit = deficit
                needy_column_i = column_i
            end
        end
        if not needy_column_i then
            break
        end

        local donor_column_i = nil
        local biggest_spare = 0
        for column_i, chars_count_for_column_i in ipairs(widths) do
            if column_i ~= needy_column_i then
                local spare = chars_count_for_column_i
                    - target_chars_count(
                        longest_word_chars_count_in_columns[column_i]
                    )
                if spare > biggest_spare then
                    biggest_spare = spare
                    donor_column_i = column_i
                end
            end
        end
        if not donor_column_i then
            break
        end
        widths[donor_column_i] = widths[donor_column_i] - 1
        widths[needy_column_i] = widths[needy_column_i] + 1
    end

    return widths
end

---@param word string
---@param chars_count_for_column_i integer
---@return string[]
local function hard_split_word(word, chars_count_for_column_i)
    local pieces = {} ---@type string[]
    local total = str.width(word)
    local col = 1
    while col <= total do
        local piece = str.sub(word, col, col + chars_count_for_column_i - 1)
        if piece == '' then
            break
        end
        pieces[#pieces + 1] = piece
        col = col + str.width(piece)
    end
    if #pieces == 0 then
        pieces[1] = word
    end
    return pieces
end

---A wrapped line shorter than its column is stored with spaces filling the rest.
---@param line string
---@param chars_count_for_column_i integer
---@return string
local function line_with_spaces_appended(line, chars_count_for_column_i)
    local missing_chars_count = chars_count_for_column_i - str.width(line)
    if missing_chars_count > 0 then
        return line .. str.pad(missing_chars_count)
    end
    return line
end

---@param wrapped_contents string[]
---@param chars_count_for_column_i integer
---@return string[]
local function wrapped_contents_padded_to_column(
    wrapped_contents,
    chars_count_for_column_i
)
    if #wrapped_contents == 0 then
        wrapped_contents[1] = ''
    end
    for line_index, line in ipairs(wrapped_contents) do
        wrapped_contents[line_index] =
            line_with_spaces_appended(line, chars_count_for_column_i)
    end
    return wrapped_contents
end

---@param cell_contents string
---@param chars_count_for_column_i integer
---@return string[]
local function wrap_contents(cell_contents, chars_count_for_column_i)
    if chars_count_for_column_i < 1 then
        chars_count_for_column_i = 1
    end
    if
        cell_contents == ''
        or str.width(cell_contents) <= chars_count_for_column_i
    then
        return wrapped_contents_padded_to_column(
            { cell_contents },
            chars_count_for_column_i
        )
    end

    local words = {} ---@type string[]
    for word in cell_contents:gmatch('%S+') do
        words[#words + 1] = word
    end
    if #words == 0 then
        return wrapped_contents_padded_to_column(
            { cell_contents },
            chars_count_for_column_i
        )
    end

    local wrapped_contents = {} ---@type string[]
    local current_line = ''

    local function flush_current_line()
        wrapped_contents[#wrapped_contents + 1] = current_line
        current_line = ''
    end

    ---@param word string
    local function place_word(word)
        local room = chars_count_for_column_i
        if current_line ~= '' then
            room = chars_count_for_column_i - str.width(current_line) - 1
        end
        if str.width(word) <= room then
            if current_line == '' then
                current_line = word
            else
                current_line = current_line .. ' ' .. word
            end
            return
        end
        if current_line ~= '' then
            flush_current_line()
        end
        if str.width(word) <= chars_count_for_column_i then
            current_line = word
            return
        end
        local pieces = hard_split_word(word, chars_count_for_column_i)
        for piece_index, piece in ipairs(pieces) do
            current_line = piece
            if piece_index < #pieces then
                flush_current_line()
            end
        end
    end

    for _, word in ipairs(words) do
        place_word(word)
    end
    if current_line ~= '' then
        wrapped_contents[#wrapped_contents + 1] = current_line
    end
    return wrapped_contents_padded_to_column(
        wrapped_contents,
        chars_count_for_column_i
    )
end

---@param actual_lines string[]
---@param index integer
---@param appended_stuff string
local function upsert_appended_stuff(actual_lines, index, appended_stuff)
    local current = actual_lines[index] or ''
    actual_lines[index] = current .. appended_stuff
end

---Separators on a content line are `table_columns + 1`: one before the first
---cell, then one after every cell.
---@param row render.md.table.text.Row
---@param chars_count_for_columns integer[]
---@param padding integer
---@param vertical_separator string
---@param row_prefix_text string
---@return string[]
local function actual_lines_of_this_row_with_wrapped_cells(
    row,
    chars_count_for_columns,
    padding,
    vertical_separator,
    row_prefix_text
)
    local table_columns = #chars_count_for_columns
    local wrapped_contents_per_column = {} ---@type string[][]
    local row_height = 1
    for column_i = 1, table_columns do
        local chars_count_for_column_i = chars_count_for_columns[column_i]
        local wrapped_contents =
            wrap_contents(row.cells[column_i] or '', chars_count_for_column_i)
        wrapped_contents_per_column[column_i] = wrapped_contents
        if #wrapped_contents > row_height then
            row_height = #wrapped_contents
        end
    end

    local actual_lines = {} ---@type string[]
    local padding_spaces = str.pad(padding)
    for line_index = 1, row_height do
        for column_i = 1, table_columns do
            local chars_count_for_column_i = chars_count_for_columns[column_i]
            local line = wrapped_contents_per_column[column_i][line_index] or ''
            line = line_with_spaces_appended(line, chars_count_for_column_i)
            if column_i == 1 then
                upsert_appended_stuff(
                    actual_lines,
                    line_index,
                    vertical_separator
                )
            end
            upsert_appended_stuff(actual_lines, line_index, padding_spaces)
            upsert_appended_stuff(actual_lines, line_index, line)
            upsert_appended_stuff(actual_lines, line_index, padding_spaces)
            upsert_appended_stuff(actual_lines, line_index, vertical_separator)
        end
        actual_lines[line_index] = row_prefix_text .. actual_lines[line_index]
    end
    return actual_lines
end

---@param span integer
---@param horizontal_separator string
---@param alignment render.md.table.col.Alignment
---@param show_alignment boolean
---@param alignment_indicator string
---@return string
local function fill_of_column(
    span,
    horizontal_separator,
    alignment,
    show_alignment,
    alignment_indicator
)
    local use_indicator = show_alignment
        and str.width(alignment_indicator) == 1
        and span >= 3
        and alignment ~= Parser.Alignment.default
    if not use_indicator then
        return horizontal_separator:rep(span)
    end
    if alignment == Parser.Alignment.left then
        return alignment_indicator .. horizontal_separator:rep(span - 1)
    end
    if alignment == Parser.Alignment.right then
        return horizontal_separator:rep(span - 1) .. alignment_indicator
    end
    return alignment_indicator
        .. horizontal_separator:rep(span - 2)
        .. alignment_indicator
end

---@param row_prefix_text string
---@param left string
---@param mid string
---@param right string
---@param horizontal_separator string
---@param chars_count_for_columns integer[]
---@param padding integer
---@param alignments render.md.table.col.Alignment[]
---@param show_alignment boolean
---@param alignment_indicator string
---@return string
local function horizontal_line(
    row_prefix_text,
    left,
    mid,
    right,
    horizontal_separator,
    chars_count_for_columns,
    padding,
    alignments,
    show_alignment,
    alignment_indicator
)
    local parts = {} ---@type string[]
    for column_i, chars_count_for_column_i in ipairs(chars_count_for_columns) do
        local span = chars_count_for_column_i + (padding * 2)
        parts[column_i] = fill_of_column(
            span,
            horizontal_separator,
            alignments[column_i],
            show_alignment,
            alignment_indicator
        )
    end
    return row_prefix_text .. left .. table.concat(parts, mid) .. right
end

---@param block_lines string[]
---@return { rows: render.md.table.text.Row[], alignments: render.md.table.col.Alignment[], prefix: string }?
local function parsed_table(block_lines)
    local prefix = row_prefix(block_lines[1])
    local parsed = {} ---@type { cells: string[], delim: boolean, align?: render.md.table.col.Alignment[] }[]
    local delim_at = nil ---@type integer?
    for _, line in ipairs(block_lines) do
        local cells = split_cells(line)
        if not cells then
            return nil
        end
        local aligns = {} ---@type render.md.table.col.Alignment[]
        local is_delim = #cells > 0
        for _, cell in ipairs(cells) do
            local align = alignment_of_delimiter_cell(cell)
            if not align then
                is_delim = false
                break
            end
            aligns[#aligns + 1] = align
        end
        if is_delim and not delim_at then
            delim_at = #parsed + 1
            parsed[#parsed + 1] =
                { cells = cells, delim = true, align = aligns }
        else
            parsed[#parsed + 1] = { cells = cells, delim = false }
        end
    end
    if not delim_at then
        return nil
    end

    local alignments = parsed[delim_at].align or {}
    local table_columns = #alignments
    if table_columns == 0 then
        return nil
    end

    local rows = {} ---@type render.md.table.text.Row[]
    for i, row in ipairs(parsed) do
        if not row.delim then
            local cells = {} ---@type string[]
            for column_i = 1, table_columns do
                cells[column_i] = row.cells[column_i] or ''
            end
            rows[#rows + 1] = { cells = cells, header = i < delim_at }
        end
    end
    if #rows == 0 then
        return nil
    end
    return { rows = rows, alignments = alignments, prefix = prefix }
end

---Pretty-print one pipe table fitted to `total_document_columns_size`.
---@param block_lines string[]
---@param total_document_columns_size integer
---@param opts? render.md.table.text.Opts
---@return render.md.table.text.Block?
function M.block(block_lines, total_document_columns_size, opts)
    opts = opts or {}
    local padding = opts.padding or 1
    local border = opts.border or default_border
    local alignment_indicator = opts.indicator or '━'
    if #block_lines == 0 or #border < 11 then
        return nil
    end

    local parsed = parsed_table(block_lines)
    if not parsed then
        return nil
    end

    local rows = parsed.rows
    local alignments = parsed.alignments
    local row_prefix_text = parsed.prefix
    local table_columns = #alignments
    local chars_count_for_row_prefix = str.width(row_prefix_text)
    local reserved = chars_count_reserved_for_cell_content(
        total_document_columns_size,
        table_columns,
        padding,
        chars_count_for_row_prefix
    )
    local measured = max_chars_count_in_columns(rows, table_columns)
    local widths = chars_count_for_columns_covering_longest_words(
        chars_count_for_columns(measured, reserved),
        longest_word_chars_count_in_columns(rows, table_columns),
        reserved
    )

    local top_left, top_mid, top_right = border[1], border[2], border[3]
    local mid_left, mid_mid, mid_right = border[4], border[5], border[6]
    local bottom_left, bottom_mid, bottom_right =
        border[7], border[8], border[9]
    local vertical_separator = border[10]
    local horizontal_separator = border[11]

    local lines = {} ---@type string[]
    local kinds = {} ---@type string[]
    ---@param text string
    ---@param kind string
    local function add(text, kind)
        lines[#lines + 1] = text
        kinds[#kinds + 1] = kind
    end

    ---@param left string
    ---@param mid string
    ---@param right string
    ---@param show_alignment boolean
    ---@return string
    local function rule(left, mid, right, show_alignment)
        return horizontal_line(
            row_prefix_text,
            left,
            mid,
            right,
            horizontal_separator,
            widths,
            padding,
            alignments,
            show_alignment,
            alignment_indicator
        )
    end

    local header_drawn = false
    local body_drawn = false
    for _, row in ipairs(rows) do
        local content = actual_lines_of_this_row_with_wrapped_cells(
            row,
            widths,
            padding,
            vertical_separator,
            row_prefix_text
        )
        if row.header then
            if not header_drawn then
                add(rule(top_left, top_mid, top_right, false), 'head')
                header_drawn = true
            else
                add(rule(mid_left, mid_mid, mid_right, false), 'head')
            end
            for _, line in ipairs(content) do
                add(line, 'head')
            end
        else
            if header_drawn and not body_drawn then
                add(rule(mid_left, mid_mid, mid_right, true), 'head')
                body_drawn = true
            elseif not body_drawn then
                add(rule(top_left, top_mid, top_right, false), 'row')
                body_drawn = true
            else
                add(rule(mid_left, mid_mid, mid_right, false), 'row')
            end
            for _, line in ipairs(content) do
                add(line, 'row')
            end
        end
    end
    if header_drawn and not body_drawn then
        add(rule(mid_left, mid_mid, mid_right, true), 'head')
    end
    add(rule(bottom_left, bottom_mid, bottom_right, false), 'row')

    return { lines = lines, kinds = kinds }
end

---Replace pipe-table rows with pretty-printed text and wrap everything else.
---`rows` is keyed by 0-based source row. `kinds` is parallel to the returned
---lines: `'head'`, `'row'`, or false.
---@param src_lines string[]
---@param rows table<integer, boolean>
---@param total_document_columns_size integer
---@param opts? render.md.table.text.Opts
---@return string[], table<integer, integer>, (string|false)[]
function M.lines(src_lines, rows, total_document_columns_size, opts)
    local out = {} ---@type string[]
    local map = {} ---@type table<integer, integer>
    local kinds = {} ---@type (string|false)[]
    local index = 1
    while index <= #src_lines do
        if rows[index - 1] then
            local first = #out
            local block = {} ---@type string[]
            while index <= #src_lines and rows[index - 1] do
                map[index - 1] = first
                block[#block + 1] = src_lines[index]
                index = index + 1
            end
            local rendered = M.block(block, total_document_columns_size, opts)
            local chunk = rendered and rendered.lines
                or wrap.lines(block, {}, total_document_columns_size)
            local chunk_kinds = rendered and rendered.kinds or nil
            for i, line in ipairs(chunk) do
                out[#out + 1] = line
                kinds[#kinds + 1] = chunk_kinds and chunk_kinds[i] or false
            end
        else
            map[index - 1] = #out
            for _, line in
                ipairs(wrap.line(src_lines[index], total_document_columns_size))
            do
                out[#out + 1] = line
                kinds[#kinds + 1] = false
            end
            index = index + 1
        end
    end
    if #out == 0 then
        out[1] = ''
        kinds[1] = false
    end
    return out, map, kinds
end

return M
