#!/usr/bin/env python3
"""SegaG80 MRA generator (engine: RodimusCoresMaster_MiSTer/tools/mra_lib.py).

    gen_mra.py <releases_dir> [set ...]     the six shipped parents (astrob 005 spaceod monsterb pignewt sindbadm)
    gen_mra.py --check

MAME driver segag80r.cpp (Useful Information/mame/). Game-ID block (index 1) byte 0 = the board variant the
dispatcher decodes as game_id: 0 astrob, 1 monsterb, 2 spaceod, 3 005, 4 sindbadm, 5 pignewt.

ROM indexes (each MAME region -> the dispatcher's ioctl_index decode; REGION_OVERRIDE below). 3 and 4 are the fleet's
hiscore config / dump (hiscore.v) and carry no ROM:
    0 maincpu (rom0)       2 Astro Blaster speech 8035 program   5 005 tune ROM          6 Sindbad sound program /
    7 bg tile planes       8 bg tile map                          9 Monster Bash 7751 samples   Monster Bash 7751 program
    10 005 divisor PROM    11 Astro Blaster speech data          12 Astro Blaster video PROMs / Monster Bash music PROM
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, "/Work/Projects/RodimusCoresMaster_MiSTer/tools")
import mra_lib                                    # noqa: E402


class SegaG80(mra_lib.Core):
    RBF = "SegaG80"
    MAME_VERSION = "0270"
    MRA_TIMESTAMP = "20261105000000"
    DRIVERS = ["segag80r.cpp"]
    PLAYERS = "2 (alternating)"
    DEFAULT_CATEGORY = "Shooter"

    SUPPORTED = {("astrob", "init_astrob"): 0, ("monsterb", "init_monsterb"): 1, ("spaceod", "init_spaceod"): 2,
                 ("sega005", "init_005"): 3, ("sindbadm", "init_sindbadm"): 4, ("pignewt", "init_pignewt"): 5}
    WORKING_HERE = {"astrob", "005", "spaceod", "monsterb", "pignewt", "sindbadm"}
    SHIPPED = ["astrob", "005", "spaceod", "monsterb", "pignewt", "sindbadm"]
    SKIP = {n: "clone / variant, not shipped (the core ships the six parents)" for n in
            ("astrob2", "astrob2a", "astrob2b", "astrob1", "astrobf", "astrobg", "005a", "spaceod2", "monsterb2", "pignewta")}

    SERIES_BY_PARENT = {"astrob": ("Astro Blaster", "Shooter"), "005": ("005", "Shooter"),
                        "spaceod": ("Space Odyssey", "Shooter"), "monsterb": ("Monster Bash", "Shooter"),
                        "pignewt": ("Pig Newton", "Action"), "sindbadm": ("Sindbad Mystery", "Action")}

    # DIP bytes in MRA order: D3D2 (switch bank 1) = DIP byte 0, D1D0 (coinage) = byte 1
    PORTS = [("D7D6",), ("D5D4",), ("D3D2",), ("D1D0",), ("FC",), ("SERVICESW",)]

    BUTTONS_BY_MACHINE = {"astrob": {1: "Shoot", 2: "Warp"}, "sega005": {1: "Shoot"}, "spaceod": {1: "Fire", 2: "Bomb"},
                          "monsterb": {1: "Fire"}, "pignewt": {1: "Action"}, "sindbadm": {1: "Action"}}

    REGIONS = {"maincpu": (0, 0xC000)}
    # region -> (ioctl index, base, size); None = not sent
    REGION_OVERRIDE = {
        "astrob":   {"speech:cpu": (2, 0, 0x800), "speech:data": (11, 0, 0x4000), "proms": (12, 0, 0x420),
                     "speech:proms": None},
        "sega005":  {"005": (5, 0, 0x800), "proms": (10, 0, 0x20)},
        "spaceod":  {"gfx1": (7, 0, 0x6000), "gfx2": (8, 0, 0x4000)},
        "monsterb": {"soundbrd:audiocpu": (6, 0, 0x400), "gfx1": (7, 0, 0x10000), "gfx2": (8, 0, 0x2000),
                     "soundbrd:upd7751": (9, 0, 0x2000), "prom": (12, 0, 0x20)},
        "pignewt":  {"gfx1": (7, 0, 0x10000), "gfx2": (8, 0, 0x4000)},
        "sindbadm": {"audiocpu": (6, 0, 0x2000), "gfx1": (7, 0, 0x4000), "gfx2": (8, 0, 0x8000)},
    }

    # unloaded tails the dispatcher's ROM blocks expect filled: (region, offset, length, value)
    FILLS = {"astrob":  [("maincpu", 0xA000, 0x2000, 0xFF), ("proms", 0x20, 0x3E0, 0xFF)],
             "005":     [("maincpu", 0xA800, 0x1800, 0xFF)],
             "spaceod": [("maincpu", 0x9800, 0x2800, 0xFF)],
             "pignewt": [("maincpu", 0xB000, 0x0800, 0xFF), ("gfx2", 0x3000, 0x1000, 0x00)]}

    # hiscore: RAM pool block 0 (main work RAM $C800-$CFFF) port B, which decodes hs_address[10:0]: every dat address
    # is in that window and passes unchanged. START_WAIT = (init frame + 2) frames, init frame = the last frame the
    # dat bytes are written during boot, MEASURED with a write tap on every dat range:
    #   MAME (40 s, headless Lua tap):   astrob 1, 005 1, spaceod 1, monsterb 264, pignewt 2
    #   this core (Verilator +hstrace, 700 frames, no coin): astrob 1, 005 2, spaceod 2, monsterb 237, pignewt 2
    # The core's numbers are used (the hardware runs this RTL, not MAME). monsterb: the game re-runs its RAM init once
    # more (clears the 3 score bytes) after the first one, frame 237 here / 264 in MAME.
    CLK_HZ, FRAME_HZ = 15468480, 60.0           # clk_sys; (15.46848 MHz / 3) / (328 x 262) = 60.000 Hz
    HISCORE_INIT_FRAME = {"astrob": 1, "005": 2, "spaceod": 2, "monsterb": 237, "pignewt": 2}
    # Sindbad Mystery: the dat's $E3A0 (60 B) range is video RAM (pool block 1, port B = video scan): no hiscore path
    # to it yet, so no hiscore blocks for this set (user 2026-11-05).
    HISCORE_SKIP = {"sindbadm"}

    def pre_place(self, segs, g, variant):
        for region, off, ln, val in self.FILLS.get(g["name"], []):
            segs.append(dict(name=None, crc=None, fill=val, src=0, dst=off, len=ln, region=region, rsize=off + ln))
        return segs

    def mra(self, g, games, with_art=False):
        t = super().mra(g, games, with_art)
        t = t.replace("<platform></platform>", "<platform>Sega G-80 Raster</platform>")
        return t.replace("<flip>yes</flip>", "<flip>no</flip>")

    def dsnd_xml(self, g):
        """every ROM index other than 0 / 2 (the engine's own two): one <rom> per index, ascending."""
        placed = self.placed(g, self.variant(g))
        zipname = f'{g["name"]}.zip' + (f'|{g["parent"]}.zip' if g["parent"] else "")
        out = ""
        for idx in sorted(i for i in placed if i not in (0, 2)):
            segs = placed[idx]
            lines, pos = [], 0
            for x in segs:
                if x["addr"] > pos:
                    lines.append(f'        <part repeat="0x{x["addr"] - pos:X}">00</part>')
                if x.get("fill") is not None:
                    lines.append(f'        <part repeat="0x{x["len"]:X}">{x["fill"]:02X}</part>')
                elif mra_lib.whole_file(x, segs):
                    lines.append(f'        <part crc="{x["crc"]}" name="{x["name"]}"/>')
                else:
                    lines.append(f'        <part crc="{x["crc"]}" name="{x["name"]}" offset="0x{x["src"]:X}" length="0x{x["len"]:X}"/>')
                pos = x["addr"] + x["len"]
            out += f'\n    <!-- Index {idx}: ROM -->\n    <rom index="{idx}" md5="none" zip="{zipname}">\n' + "\n".join(lines) + "\n    </rom>\n"
        return out


if __name__ == "__main__":
    c = SegaG80()
    c.main(sys.argv if len(sys.argv) != 2 or sys.argv[1] == "--check" else sys.argv + c.SHIPPED)
