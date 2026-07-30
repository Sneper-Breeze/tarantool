local server = require('luatest.server')
local t = require('luatest')

local g = t.group()

g.before_all(function(cg)
    cg.server = server:new()
    cg.server:start()
end)

g.after_all(function(cg)
    cg.server:drop()
end)

g.after_each(function(cg)
    cg.server:exec(function()
        if box.space.test ~= nil then
            box.space.test:drop()
        end
    end)
end)

-- Create space 'test' with a primary index; the 'value' field is
-- declared with the given is_nullable option.
local function create_test_space(cg, value_is_nullable)
    cg.server:exec(function(value_is_nullable)
        local space = box.schema.space.create('test')
        space:format({
            {name = 'id', type = 'unsigned'},
            {name = 'value', type = 'unsigned',
             is_nullable = value_is_nullable},
        })
        space:create_index('pk')
    end, {value_is_nullable})
end

-- Create a secondary index on the 'value' field with the given
-- is_nullable key part option.
local function create_index(cg, name, is_nullable)
    cg.server:exec(function(name, is_nullable)
        box.space.test:create_index(name, {
            parts = {{field = 'value', is_nullable = is_nullable}},
        })
    end, {name, is_nullable})
end

local function alter_index(cg, name, is_nullable)
    cg.server:exec(function(name, is_nullable)
        box.space.test.index[name]:alter({
            parts = {{field = 'value', is_nullable = is_nullable}},
        })
    end, {name, is_nullable})
end

local function drop_index(cg, name)
    cg.server:exec(function(name)
        box.space.test.index[name]:drop()
    end, {name})
end

-- Assert that both public format views (space:format() and
-- space.format_object) report the given is_nullable for a field.
local function assert_field_nullable(cg, field_no, expected)
    cg.server:exec(function(field_no, expected)
        local space = box.space.test
        t.assert_equals(space:format()[field_no].is_nullable, expected)
        t.assert_equals(
            space.format_object:totable()[field_no].is_nullable, expected)
    end, {field_no, expected})
end

-- Assert that a field's is_nullable option is absent (not exported)
-- in both public format views.
local function assert_field_nullable_absent(cg, field_no)
    cg.server:exec(function(field_no)
        local space = box.space.test
        t.assert_equals(space:format()[field_no].is_nullable, nil)
        t.assert_equals(
            space.format_object:totable()[field_no].is_nullable, nil)
    end, {field_no})
end

-- Assert that replacing a tuple with NULL in the nullable field
-- succeeds, consistently with the reported nullable format.
local function assert_null_replace_ok(cg)
    cg.server:exec(function()
        local space = box.space.test
        space:replace{1, box.NULL}
        space:delete{1}
    end)
end

-- Assert that replacing/validating a tuple with NULL fails,
-- consistently with the reported non-nullable format.
local function assert_null_replace_fails(cg)
    cg.server:exec(function()
        local space = box.space.test
        t.assert_error(space.replace, space, {1, box.NULL})
        t.assert_error(space.format_object.validate, space.format_object,
                       {1, box.NULL})
    end)
end

-- Create a non-nullable secondary index on a nullable field: the
-- reported format must become non-nullable, and NULL must be rejected.
g.test_index_create_makes_nullable_visible_false = function(cg)
    create_test_space(cg, true)
    assert_field_nullable(cg, 2, true)

    create_index(cg, 'value', false)

    assert_field_nullable(cg, 2, false)
    assert_null_replace_fails(cg)
end

-- Alter a non-nullable index to nullable: the reported format must
-- become nullable again, and NULL must be accepted.
g.test_index_alter_to_nullable_makes_visible_true = function(cg)
    create_test_space(cg, true)
    create_index(cg, 'value', false)
    assert_field_nullable(cg, 2, false)

    alter_index(cg, 'value', true)

    assert_field_nullable(cg, 2, true)
    assert_null_replace_ok(cg)
end

-- Drop a non-nullable index that was tightening a nullable field: the
-- reported format must be restored to nullable.
g.test_index_drop_restores_nullable = function(cg)
    create_test_space(cg, true)
    create_index(cg, 'value', false)
    assert_field_nullable(cg, 2, false)

    drop_index(cg, 'value')

    assert_field_nullable(cg, 2, true)
    assert_null_replace_ok(cg)
end

-- Two non-nullable indexes on the same nullable field: dropping one
-- must not restore nullability; dropping the last one must.
g.test_multiple_non_nullable_indexes = function(cg)
    create_test_space(cg, true)
    create_index(cg, 'sk1', false)
    create_index(cg, 'sk2', false)
    assert_field_nullable(cg, 2, false)

    drop_index(cg, 'sk1')
    assert_field_nullable(cg, 2, false)

    drop_index(cg, 'sk2')
    assert_field_nullable(cg, 2, true)
end

-- A field without an explicit is_nullable in the original format must
-- stay absent in both views, even after a non-nullable index.
g.test_omitted_is_nullable_stays_absent = function(cg)
    create_test_space(cg, nil)

    create_index(cg, 'value', false)

    assert_field_nullable_absent(cg, 1)
    assert_field_nullable_absent(cg, 2)
end
