local T = require 'harness'
local test, eq, same, pack = T.test, T.eq, T.same, T.pack

test('get_catalog returns the same catalog for a name', function(L)
  local catalog = L.catalog
  eq(catalog.get_catalog('x'), catalog.get_catalog('x'))
  T.ok(catalog.get_catalog('x') ~= catalog.get_catalog('y'))
end)

test('a registered object can be looked up by name and back', function(L)
  local cat = L.catalog.get_catalog('things', true)
  local obj = {}
  eq(cat:register('name', obj), true)
  eq(cat:register('name', obj), true, 'registering again is fine')
  local found
  L.sched.run(function() found = cat:waitfor('name') end)
  eq(found, obj)
  eq(cat:namefor(obj), 'name')
  eq(cat:namefor({}), nil)
end)

test('a name can not be given to two objects', function(L)
  local cat = L.catalog.get_catalog('things', true)
  local a, b = {}, {}
  cat:register('name', a)
  same(pack(cat:register('name', b)), {n = 2, nil, 'used'})
  eq(cat:namefor(b), nil)
end)

test('an object can only be renamed when forced', function(L)
  local cat = L.catalog.get_catalog('things', true)
  local obj = {}
  cat:register('old', obj)
  same(pack(cat:register('new', obj)), {n = 2, nil, 'present'})
  eq(cat:register('new', obj, true), true)
  eq(cat:namefor(obj), 'new')
  eq(cat.direct.old, nil, 'old name released')
  eq(cat:register('old', {}), true)
end)

test('unregister removes the name', function(L)
  local cat = L.catalog.get_catalog('things', true)
  local obj = {}
  cat:register('name', obj)
  eq(cat:unregister('name'), true)
  eq(cat:namefor(obj), nil)
  same(pack(cat:unregister('name')), {n = 2, nil, 'missing'})
end)

test('waitfor blocks until the name is registered', function(L)
  local sched = L.sched
  local cat = L.catalog.get_catalog('things', true)
  local obj, found = {}, {}
  for i = 1, 2 do
    sched.run(function() found[i] = cat:waitfor('later') end)
  end
  eq(found[1], nil)
  sched.run(function()
    sched.sleep(2)
    cat:register('later', obj)
  end)
  L.loop()
  same(found, {obj, obj})
  eq(L.now, 2)
end)

test('waitfor times out', function(L)
  local cat = L.catalog.get_catalog('things', true)
  local got
  L.sched.run(function() got = pack(cat:waitfor('never', 3)) end)
  L.loop()
  same(got, {n = 2, nil, 'timeout'})
  eq(L.now, 3)
end)

test('iterator lists the registered objects', function(L)
  local cat = L.catalog.get_catalog('things', true)
  local a, b = {}, {}
  cat:register('a', a)
  cat:register('b', b)
  local seen = {}
  for name, obj in cat:iterator() do seen[name] = obj end
  same(seen, {a = a, b = b})
end)

test('weak catalogs do not keep objects alive, strong ones do', function(L)
  local weak = L.catalog.get_catalog('weak')
  local strong = L.catalog.get_catalog('strong', true)
  weak:register('obj', {})
  strong:register('obj', {})
  collectgarbage('collect')
  eq(weak.direct.obj, nil)
  T.ok(strong.direct.obj)
end)
