--- Run the Lumen test suite.
-- Usage: lua spec/run.lua [filter]
-- Runs every spec/*_spec.lua file; filter, if given, selects tests whose
-- "file: name" contains it (plain substring).

local root = (arg and arg[0] or ''):match('^(.-)[/\\]?spec[/\\]run%.lua$') or '.'
if root == '' then root = '.' end

package.path = root..'/spec/?.lua;'..package.path

-- resolve lumen.* modules from this checkout, whatever its directory is named
local function lumen_searcher(name)
  if name ~= 'lumen' and name:sub(1, 6) ~= 'lumen.' then return nil end
  local rel = name == 'lumen' and 'init' or name:sub(7):gsub('%.', '/')
  local tried = {}
  for _, path in ipairs({root..'/'..rel..'.lua', root..'/'..rel..'/init.lua'}) do
    local f = io.open(path)
    if f then
      f:close()
      return assert(loadfile(path))
    end
    tried[#tried+1] = '\n\tno file '..path
  end
  return table.concat(tried)
end
local searchers = package.searchers or package.loaders
table.insert(searchers, 2, lumen_searcher)

local harness = require 'harness'

local spec_files = {
  'lib_spec.lua',
  'log_spec.lua',
  'sched_spec.lua',
  'pipe_spec.lua',
  'stream_spec.lua',
  'mutex_spec.lua',
  'catalog_spec.lua',
  'selector_spec.lua',
}

for _, file in ipairs(spec_files) do
  harness.current_file = file:gsub('_spec%.lua$', '')
  dofile(root..'/spec/'..file)
end

os.exit(harness.run(arg[1]) and 0 or 1)
