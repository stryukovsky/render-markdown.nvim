---@module 'luassert'

local util = require('tests.util')

describe('document symbols', function()
    local lsp = require('render-markdown.integ.lsp')
    local kind = vim.lsp.protocol.SymbolKind.String

    ---@param name string
    ---@param range integer[]
    ---@param selection integer[]
    ---@param children? lsp.DocumentSymbol[]
    ---@return lsp.DocumentSymbol
    local function symbol(name, range, selection, children)
        ---@type lsp.DocumentSymbol
        return {
            name = name,
            kind = kind,
            range = {
                start = { line = range[1], character = range[2] },
                ['end'] = { line = range[3], character = range[4] },
            },
            selectionRange = {
                start = { line = selection[1], character = selection[2] },
                ['end'] = { line = selection[3], character = selection[4] },
            },
            children = children,
        }
    end

    ---@param lines string[]
    ---@param encoding render.md.lsp.Encoding
    ---@return lsp.DocumentSymbol[]
    local function symbols(lines, encoding)
        util.setup.text(lines)
        return lsp.symbols(0, encoding) or {}
    end

    it('nests atx headings by level', function()
        local lines = {
            'intro',
            '',
            '# Alpha',
            '',
            'body',
            '',
            '## Beta',
            '',
            '### Gamma',
            '',
            '## Delta',
            '',
            '# Epsilon',
        }
        assert.same({
            symbol('Alpha', { 2, 0, 12, 0 }, { 2, 2, 2, 7 }, {
                symbol('Beta', { 6, 0, 10, 0 }, { 6, 3, 6, 7 }, {
                    symbol('Gamma', { 8, 0, 10, 0 }, { 8, 4, 8, 9 }),
                }),
                symbol('Delta', { 10, 0, 12, 0 }, { 10, 3, 10, 8 }),
            }),
            symbol('Epsilon', { 12, 0, 13, 0 }, { 12, 2, 12, 9 }),
        }, symbols(lines, 'utf-8'))
    end)

    it('includes setext headings in the same outline', function()
        local lines = {
            'Title',
            '=====',
            '',
            'paragraph',
            '',
            'Child',
            '-----',
            '',
            '### Nested',
            '',
            '# After',
        }
        assert.same({
            symbol('Title', { 0, 0, 10, 0 }, { 0, 0, 0, 5 }, {
                symbol('Child', { 5, 0, 10, 0 }, { 5, 0, 5, 5 }, {
                    symbol('Nested', { 8, 0, 10, 0 }, { 8, 4, 8, 10 }),
                }),
            }),
            symbol('After', { 10, 0, 11, 0 }, { 10, 2, 10, 7 }),
        }, symbols(lines, 'utf-8'))
    end)

    it('joins a multiline setext title', function()
        local lines = {
            'Foo',
            'Bar',
            '===',
        }
        assert.same({
            symbol('Foo Bar', { 0, 0, 3, 0 }, { 0, 0, 1, 3 }),
        }, symbols(lines, 'utf-8'))
    end)

    it('drops atx closing hashes from the name', function()
        local lines = { '# Title ##', '', '## Kept' }
        assert.same({
            symbol('Title', { 0, 0, 3, 0 }, { 0, 2, 0, 7 }, {
                symbol('Kept', { 2, 0, 3, 0 }, { 2, 3, 2, 7 }),
            }),
        }, symbols(lines, 'utf-8'))
    end)

    it('skips blank headings and non-headings', function()
        local lines = {
            '---',
            'title: foo',
            '---',
            '',
            '#',
            '',
            '```lua',
            '# comment',
            '```',
            '',
            '    # indented',
            '',
            '#no-space',
            '',
            '## Kept',
        }
        assert.same({
            symbol('Kept', { 14, 0, 15, 0 }, { 14, 3, 14, 7 }),
        }, symbols(lines, 'utf-8'))
    end)

    it('keeps headings inside quotes and lists', function()
        local lines = {
            '# Outside',
            '',
            '> ## Inside',
            '',
            '- ### Item',
            '',
            '## After',
        }
        assert.same({
            symbol('Outside', { 0, 0, 7, 0 }, { 0, 2, 0, 9 }, {
                symbol('Inside', { 2, 2, 6, 0 }, { 2, 5, 2, 11 }, {
                    symbol('Item', { 4, 2, 6, 0 }, { 4, 6, 4, 10 }),
                }),
                symbol('After', { 6, 0, 7, 0 }, { 6, 3, 6, 8 }),
            }),
        }, symbols(lines, 'utf-8'))
    end)

    it('encodes multibyte columns', function()
        local lines = { '# Привет', '', '## 🕛' }
        local utf8 = {
            symbol('Привет', { 0, 0, 3, 0 }, { 0, 2, 0, 14 }, {
                symbol('🕛', { 2, 0, 3, 0 }, { 2, 3, 2, 7 }),
            }),
        }
        local utf16 = {
            symbol('Привет', { 0, 0, 3, 0 }, { 0, 2, 0, 8 }, {
                symbol('🕛', { 2, 0, 3, 0 }, { 2, 3, 2, 5 }),
            }),
        }
        assert.same(utf8, symbols(lines, 'utf-8'))
        assert.same(utf16, symbols(lines, 'utf-16'))
    end)

    it('answers documentSymbol for the attached buffer', function()
        util.setup.text({ '# Alpha', '', '## Beta' })
        local uri = vim.uri_from_bufnr(0)
        ---@type vim.lsp.rpc.Dispatchers
        local dispatchers = {
            notification = function() end,
            server_request = function() end,
            on_exit = function() end,
            on_error = function() end,
        }
        local client = lsp.server(dispatchers)
        local init ---@type lsp.InitializeResult?
        client.request('initialize', {
            capabilities = {
                general = { positionEncodings = { 'utf-8', 'utf-16' } },
            },
        }, function(_, result)
            init = result
        end)
        assert.same('utf-8', init.capabilities.positionEncoding)
        assert.same(true, init.capabilities.documentSymbolProvider)

        local got ---@type lsp.DocumentSymbol[]?
        client.request('textDocument/documentSymbol', {
            textDocument = { uri = uri },
        }, function(_, result)
            got = result
        end)
        assert.same({
            symbol('Alpha', { 0, 0, 3, 0 }, { 0, 2, 0, 7 }, {
                symbol('Beta', { 2, 0, 3, 0 }, { 2, 3, 2, 7 }),
            }),
        }, got)
    end)
end)
