-- Verify translated lines keep the same #n# variables as the originals.
local function load(path)
  local t, h = {}, nil
  local f = io.open(path) if not f then return t end
  for line in f:lines() do
    if line:sub(1,1) == "=" then h = line:sub(2)
    else local p, s = line:match("^([^\t]+)\t(.*)$") if p then t[h.."|"..p] = s end end
  end
  return t
end
local function vars(s) local v = {} for x in s:gmatch("#%d+#") do v[#v+1] = x end table.sort(v) return table.concat(v, ",") end
local bad = 0
for i = 1, #arg do
  local n = arg[i]
  local o, t = load("chunks/"..n), load("out/"..n)
  for p, s in pairs(t) do
    if not o[p] then print(n, "UNKNOWN", p); bad = bad + 1
    elseif vars(o[p]) ~= vars(s) and not p:find("|text|%d+$") == false then
      -- multi-line descriptions may move vars between lines; check per entry below
    end
  end
  -- per-entry var multiset check
  local function per(tbl) local e = {} for p, s in pairs(tbl) do local k = p:match("^(.*)|[^|]+$") or p e[k] = (e[k] or "") .. s end return e end
  local oe = per(o)
  local merged = {} for p, s in pairs(o) do merged[p] = t[p] or s end
  for k, s in pairs(per(merged)) do if vars(s) ~= vars(oe[k]) then print(n, "VARS", k, vars(oe[k]), "=>", vars(s)); bad = bad + 1 end end
end
print("issues", bad)
