-- Log the first N vector-RAM writes (post-scramble) so the RTL's write stream
-- can be diffed against MAME's. SEGATAP_OUT names the output file,
-- SEGATAP_N the number of writes to capture.
local outpath = os.getenv("SEGATAP_OUT") or "/tmp/mame_vram_writes.txt"
local want    = tonumber(os.getenv("SEGATAP_N")) or 400

local mac = manager.machine
local mem = mac.devices[":maincpu"].spaces["program"]
local f = io.open(outpath, "w")
local n = 0

_G.segatap = mem:install_write_tap(0xE000, 0xEFFF, "vramtap", function(offset, data, mask)
	if n < want then
		f:write(string.format("%04X %02X\n", offset, data & 0xff))
		n = n + 1
		if n == want then f:flush(); f:close() end
	end
	return data
end)

print(string.format("SEGATAP: capturing %d writes to %s", want, outpath))
