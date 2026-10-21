-- Print only entries/lines with real English text (tags and #n# stripped), skipping CBlind.
local function real(s)
  local t = s:gsub("{[^}]*}", ""):gsub("#[^#]*#", ""):gsub("https?://%S+", "")
  return t:find("%a%a") and not t:find("[\208\209][\128-\191]")
end
for i = 1, #arg do
  local f = io.open("chunks/" .. arg[i]); local out = io.open("views/" .. arg[i], "w")
  local header, buf, skip = nil, {}, false
  local function flush() if header and #buf > 0 and not skip then out:write(header, "\n", table.concat(buf, "\n"), "\n") end buf = {} end
  for line in f:lines() do
    if line:sub(1,1) == "=" then flush(); header = line; skip = line:find("^=descriptions|CBlind|") ~= nil
    else local p, s = line:match("^([^\t]+)\t(.*)$"); if s and real(s) then buf[#buf+1] = line end end
  end
  flush(); out:close()
end
