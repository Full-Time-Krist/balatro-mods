-- Merge a freshly built translation table into the existing ru.lua.
-- usage: lua merge.lua <base ru.lua> <new.lua> <target>
-- Tables are merged recursively; string arrays (text = {...}) are replaced whole,
-- the same way RuFill.lua applies them in game.
local base_path, new_path, target = arg[1], arg[2], arg[3]
local base = dofile(base_path)
local new = dofile(new_path)

local function merge(src, dst)
  for k, v in pairs(src) do
    if type(v) == "table" and type(v[1]) ~= "string" and type(dst[k]) == "table" then
      merge(v, dst[k])
    else
      dst[k] = v
    end
  end
end
merge(new, base)

local function ser(v, ind)
  if type(v) == "string" then return (string.format("%q", v):gsub("\\\n", "\\n")) end
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
local f = assert(io.open(target, "w"))
f:write("return ", ser(base, ""), "\n")
f:close()
print("merged into " .. target)
