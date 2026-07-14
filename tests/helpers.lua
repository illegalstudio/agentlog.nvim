local M = {}

local function format(value)
  return vim.inspect(value)
end

function M.eq(expected, actual, message)
  if not vim.deep_equal(expected, actual) then
    error(message or ("expected %s, got %s"):format(format(expected), format(actual)), 2)
  end
end

function M.truthy(value, message)
  if not value then
    error(message or ("expected a truthy value, got %s"):format(format(value)), 2)
  end
end

function M.falsy(value, message)
  if value then
    error(message or ("expected a falsy value, got %s"):format(format(value)), 2)
  end
end

function M.test(name, callback)
  return {
    name = name,
    run = callback,
  }
end

return M
