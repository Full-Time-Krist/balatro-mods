-- Build RuFill localization/ru.lua: original chunk lines overridden by translated out/ lines.
local chunkdir, outdir, target = arg[1], arg[2], arg[3]
local function unesc(s) return (s:gsub("\\(.)", { n = "\n", t = "\t", ["\\"] = "\\" })) end
local function parse(path, into, stats)
  local f = io.open(path) if not f then return end
  local header
  for line in f:lines() do
    if line:sub(1,1) == "=" then header = line:sub(2)
    elseif line ~= "" then
      local p, text = line:match("^([^\t]+)\t(.*)$")
      if p and header then into[header .. "|" .. p] = unesc(text); if stats then stats.n = stats.n + 1 end
      elseif stats then stats.bad[#stats.bad+1] = line end
    end
  end
  f:close()
end
local orig, tr = {}, {}
local order = {}
for name in io.popen('ls "' .. chunkdir .. '"'):lines() do
  parse(chunkdir .. "/" .. name, orig)
  local stats = { n = 0, bad = {} }
  parse(outdir .. "/" .. name, tr, stats)
  if #stats.bad > 0 then io.stderr:write(name, ": unparsable lines: ", #stats.bad, " e.g. ", stats.bad[1], "\n") end
end
local root, missing, done = {}, 0, 0
for path, text in pairs(orig) do
  if tr[path] then text = tr[path]; done = done + 1 else missing = missing + 1 end
  local node, parts = root, {}
  for seg in path:gmatch("[^|]+") do parts[#parts+1] = tonumber(seg) or seg end
  for i = 1, #parts - 1 do node[parts[i]] = node[parts[i]] or {}; node = node[parts[i]] end
  node[parts[#parts]] = text
end
local unknown = 0
for path in pairs(tr) do if not orig[path] then unknown = unknown + 1; if unknown <= 5 then io.stderr:write("unknown path: ", path, "\n") end end end
local function ser(v, ind)
  if type(v) == "string" then return string.format("%q", v):gsub("\\\n", "\\n") end
  local ks = {} for k in pairs(v) do ks[#ks+1] = k end
  table.sort(ks, function(a,b) if type(a)==type(b) then return a<b end return type(a)=="number" end)
  local o, pad = { "{\n" }, ind .. "\t"
  for _, k in ipairs(ks) do
    local key = type(k) == "number" and ("[" .. k .. "] = ") or ((k:match("^[%a_][%w_]*$") and k or string.format("[%q]", k)) .. " = ")
    o[#o+1] = pad .. key .. ser(v[k], pad) .. ",\n"
  end
  o[#o+1] = ind .. "}"
  return table.concat(o)
end
local f = io.open(target, "w"); f:write("return ", ser(root, ""), "\n"); f:close()
print(string.format("translated %d, untouched %d, unknown %d", done, missing, unknown))
