lets rethink entire rendering of tables 

config has width of line, `total_document_columns_size`
config has padding from separator of columns, `padding` - spaces to insert between separator and contents of md table cell 
for markdown table we can using treesitter identify every cell, row etc

for every row of table we can easily tell how much in wrapped mode it will take to render row 

here is pseudo code 

we has total_document_columns_size width, we need to render table of `table_columns` columns 
we have chars_count_for_separators = `table_columns` + 1 separators 
also chars_count_for_paddings = `padding` * 2 * table_columns - every cell in row has this amount of spaces 

so `chars_count_reserved_for_cell_content = total_document_columns_size - chars_count_for_paddings - chars_count_for_separators`

at this moment we havent even iterated the table 

now we need to calculate how chars_count_reserved_for_cell_content shall be distributed between columns 

!!! ITERATION OF TABLE NUMBER ONE !!!
for this we iterate all the table. goal - in every column calculate max(chars) of contents in cells
here is proportion rule
max_chars_count_in_column_i / sum_of_max_chars_count_across_columns = chars_count_for_column_i / chars_count_reserved_for_cell_content
chars_count_for_column_i - it is needed from this proportion value to tell "how wide will be this exact column"

then lets render the rows, ofc we need some special styling for first row with heading, but still we need wrapping_of_contents here 
but rendering of rows is practically the same 

ITERATION NUMBER TWO
for every row:
    draw horizontal line()
    actual_lines_of_this_row_with_wrapped_cells = []
    for every cell of row:
        identify current iterated column_i
        chars_count_for_column_i is known and can be taken from prepared state in previous iteration
        wrapped_contents = wrap_contents(cell.contents)
        for i, line in wrapped_contents:
            actual_lines_of_this_row_with_wrapped_cells.upsert(index=i, appended_stuff=separator horizontal)
            actual_lines_of_this_row_with_wrapped_cells.upsert(index=i, appended_stuff=padding)
            actual_lines_of_this_row_with_wrapped_cells.upsert(index=i, appended_stuff=line)
            actual_lines_of_this_row_with_wrapped_cells.upsert(index=i, appended_stuff=padding)
            actual_lines_of_this_row_with_wrapped_cells.upsert(index=i, appended_stuff=separator horizontal)
        

