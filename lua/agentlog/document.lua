local M = {}

local function assert_integer(value, name)
  if type(value) ~= "number" or value % 1 ~= 0 then
    error(("%s must be an integer"):format(name))
  end
end

function M.region(specification)
  if type(specification) ~= "table" then
    error("region specification must be a table")
  end

  if type(specification.kind) ~= "string" or specification.kind == "" then
    error("region kind must be a non-empty string")
  end

  assert_integer(specification.start_row, "region start_row")
  assert_integer(specification.end_row, "region end_row")

  if specification.start_row < 0 then
    error("region start_row must be zero or greater")
  end

  if specification.end_row <= specification.start_row then
    error("region end_row must be greater than start_row")
  end

  local children = {}
  for _, child in ipairs(specification.children or {}) do
    children[#children + 1] = M.region(child)
  end

  return {
    kind = specification.kind,
    start_row = specification.start_row,
    end_row = specification.end_row,
    source = specification.source or "unknown",
    confidence = specification.confidence or 1,
    metadata = vim.deepcopy(specification.metadata or {}),
    children = children,
  }
end

function M.new(specification)
  specification = specification or {}

  local regions = {}
  for _, region in ipairs(specification.regions or {}) do
    regions[#regions + 1] = M.region(region)
  end

  return {
    source = specification.source or "unknown",
    transport = specification.transport,
    regions = regions,
    metadata = vim.deepcopy(specification.metadata or {}),
  }
end

function M.walk(document, callback)
  local function visit(region)
    callback(region)
    for _, child in ipairs(region.children) do
      visit(child)
    end
  end

  for _, region in ipairs(document.regions) do
    visit(region)
  end
end

return M
