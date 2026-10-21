-- Flatten the dump into chunk files: "=header" lines, then "relpath<TAB>text".
local d = dofile(arg[1])
local outdir, maxlines = arg[2], tonumber(arg[3] or 600)
local function esc(s) return (s:gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("\t", "\\t")) end
local function sorted(t)
  local ks = {} for k in pairs(t) do ks[#ks+1] = k end
  table.sort(ks, function(a,b) if type(a)==type(b) then return a<b end return type(a)=="number" end)
  return ks
end
local function leaves(t, prefix, acc)
  if type(t) == "string" then acc[#acc+1] = prefix .. "\t" .. esc(t) return acc end
  if type(t) ~= "table" then return acc end
  for _, k in ipairs(sorted(t)) do
    if not (type(k)=="string" and k:find("_parsed$")) then
      leaves(t[k], prefix == "" and tostring(k) or (prefix .. "|" .. tostring(k)), acc)
    end
  end
  return acc
end
local blocks = {}
local function modkey(k) return k:match("^%a+_(%a+)_") or k:match("^(%a+)_") or k end
local keys = {}
for set, es in pairs(d.descriptions) do for k in pairs(es) do keys[#keys+1] = {set, k} end end
table.sort(keys, function(a,b) local ma, mb = modkey(a[2]), modkey(b[2]) if ma ~= mb then return ma < mb end if a[1] ~= b[1] then return a[1] < b[1] end return a[2] < b[2] end)
for _, sk in ipairs(keys) do
  blocks[#blocks+1] = { "=descriptions|" .. sk[1] .. "|" .. sk[2], leaves(d.descriptions[sk[1]][sk[2]], "", {}) }
end
for top, v in pairs(d) do
  if top ~= "descriptions" and not top:find("_parsed$") and type(v) == "table" then
    for _, k in ipairs(sorted(v)) do
      local ls = leaves(v[k], "", {})
      -- split big groups (misc.dictionary) into pieces
      for i = 1, #ls, 150 do
        local part = {} for j = i, math.min(i+149, #ls) do part[#part+1] = ls[j] end
        blocks[#blocks+1] = { "=" .. top .. "|" .. k, part }
      end
    end
  end
end
local n, cur, cnt = 0, nil, 0
local function flush() if cur then cur:close() end end
for _, b in ipairs(blocks) do
  if not cur or cnt + #b[2] > maxlines then
    flush(); n = n + 1; cnt = 0
    cur = io.open(string.format("%s/%03d.txt", outdir, n), "w")
  end
  cur:write(b[1], "\n")
  for _, l in ipairs(b[2]) do cur:write(l, "\n") end
  cnt = cnt + #b[2] + 1
end
flush()
print("chunks", n)
