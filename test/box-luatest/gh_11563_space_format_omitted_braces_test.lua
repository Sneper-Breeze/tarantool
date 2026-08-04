local server = require('luatest.server')
local t = require('luatest')

local g = t.group()

g.before_all(function(cg)
    cg.server = server:new()
    cg.server:start()
end)

g.after_all(function(cg)
    if cg.server ~= nil then
        cg.server:drop()
    end
end)

g.after_each(function(cg)
    cg.server:exec(function()
        if box.space.test ~= nil then
            box.space.test:drop()
        end
    end)
end)

-- Assert that box.space.test's format has exactly one field with the
-- given name and type.
local function assert_single_field(cg, name, ftype)
    cg.server:exec(function(name, ftype)
        local fmt = box.space.test:format()
        t.assert_equals(#fmt, 1)
        t.assert_equals(fmt[1].name, name)
        t.assert_equals(fmt[1].type, ftype)
    end, {name, ftype})
end

-- Reproduce the original issue: a single field-def table passed to
-- space:format() without outer braces must not silently wipe the
-- format, but be treated as a one-field format.
g.test_format_setter_wraps_bare_field_def = function(cg)
    cg.server:exec(function()
        local s = box.schema.space.create('test')
        s:format({
            {name = 'a', type = 'unsigned'},
            {name = 'b', type = 'unsigned'},
        })

        s:format({name = 'c', type = 'string'})
    end)

    assert_single_field(cg, 'c', 'string')
end

-- Explicitly passing an empty table must still clear the format: the
-- auto-wrap must not kick in for a table with no keys at all.
g.test_format_setter_empty_table_still_clears = function(cg)
    cg.server:exec(function()
        local s = box.schema.space.create('test')
        s:format({{name = 'a', type = 'unsigned'}})

        s:format({})

        t.assert_equals(#s:format(), 0)
    end)
end

-- A regular list of field-def tables must be unaffected by the
-- auto-wrap, since it already has a sequence part.
g.test_format_setter_list_of_field_defs_unaffected = function(cg)
    cg.server:exec(function()
        local s = box.schema.space.create('test')

        s:format({
            {name = 'a', type = 'unsigned'},
            {name = 'b', type = 'string'},
        })

        local fmt = s:format()
        t.assert_equals(#fmt, 2)
        t.assert_equals(fmt[1].name, 'a')
        t.assert_equals(fmt[2].name, 'b')
    end)
end

-- box.schema.space.create() shares the same normalizer: a bare
-- field-def table in options.format must be auto-wrapped too.
g.test_space_create_wraps_bare_field_def = function(cg)
    cg.server:exec(function()
        box.schema.space.create('test', {
            format = {name = 'a', type = 'unsigned'},
        })
    end)

    assert_single_field(cg, 'a', 'unsigned')
end

-- space:alter() shares the same normalizer: a bare field-def table
-- in options.format must be auto-wrapped too.
g.test_space_alter_wraps_bare_field_def = function(cg)
    cg.server:exec(function()
        local s = box.schema.space.create('test', {
            format = {{name = 'a', type = 'unsigned'}},
        })

        s:alter({format = {name = 'b', type = 'string'}})
    end)

    assert_single_field(cg, 'b', 'string')
end

-- box.tuple.format.new() shares the same normalizer: a bare
-- field-def table must be auto-wrapped too.
g.test_tuple_format_new_wraps_bare_field_def = function(cg)
    cg.server:exec(function()
        local fmt = box.tuple.format.new({name = 'a', type = 'unsigned'})

        local fmt_tbl = fmt:totable()
        t.assert_equals(#fmt_tbl, 1)
        t.assert_equals(fmt_tbl[1].name, 'a')
        t.assert_equals(fmt_tbl[1].type, 'unsigned')
    end)
end

-- A table that has both a sequence part (format[1]) and top-level
-- field-def keys ('name'/'type') is not ambiguous: the sequence part
-- wins and the table is treated as a list, not auto-wrapped.
g.test_format_setter_sequence_part_takes_priority = function(cg)
    cg.server:exec(function()
        local s = box.schema.space.create('test')
        local format = {name = 'a', type = 'unsigned'}
        format[1] = {name = 'b', type = 'string'}

        s:format(format)
    end)

    assert_single_field(cg, 'b', 'string')
end

-- A bare field-def table missing the required 'name' key must still
-- raise the usual validation error, not silently produce an empty
-- format.
g.test_format_setter_bare_field_def_without_name_still_validated = function(cg)
    cg.server:exec(function()
        local s = box.schema.space.create('test')
        s:format({{name = 'a', type = 'unsigned'}})

        t.assert_error_msg_contains(
            "format[1]: name (string) is expected",
            s.format, s, {type = 'unsigned'})
    end)

    assert_single_field(cg, 'a', 'unsigned')
end
