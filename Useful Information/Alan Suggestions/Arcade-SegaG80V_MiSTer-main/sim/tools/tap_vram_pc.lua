-- Same as tap_vram.lua but records the CPU PC with each write, to identify
-- the code responsible for a divergence.
local outpath = os.getenv("SEGATAP_OUT") or "/tmp/mame_vram_pc.txt"
local want    = tonumber(os.getenv("SEGATAP_N")) or 400
local mac = manager.machine
local cpu = mac.devices[":maincpu"]
local mem = cpu.spaces["program"]
local f = io.open(outpath, "w")
local n = 0
_G.segatap = mem:install_write_tap(0xE000, 0xEFFF, "vramtap", function(offset, data, mask)
	if n < want then
		local pc = 0
		local ok, st = pcall(function() return cpu.state["PC"].value end)
		if ok then pc = st end
		f:write(string.format("%04X %02X %04X\n", offset, data & 0xff, pc))
		n = n + 1
		if n == want then f:flush(); f:close() end
	end
	return data
end)
print("SEGATAP-PC: capturing " .. want .. " writes")
