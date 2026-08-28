#!/usr/bin/env python3
"""Generate MRA files for the Sega G-80 X-Y core.

ROM layout the core expects (identical to tools/build_rom.py, so an MRA and a
simulation image are always the same bytes):

    0x0000 - 0xBFFF   maincpu       program ROM
    0xC000 - 0xC3FF   s-c.xyt-u39   sin/cos PROM
    0xC400 - 0xCBFF   speech:cpu    speech board 8035 program (2K)
    0xCC00 - 0x10BFF  speech:data   speech board LPC data (16K)

Filenames, offsets and CRCs are parsed out of MAME's segag80v.cpp so they
cannot drift from the driver.

    make_mra.py <segag80v.cpp> <outdir> [set ...]
"""

import os
import re
import sys

# game id -> sega_game_pkg, and the OSD/DIP metadata that differs per title
GAMES = {
    'elim2':    dict(id=0, name='Eliminator (2 Players, set 1)',
                     year='1981', manuf='Gremlin'),
    'elim2a':   dict(id=0, name='Eliminator (2 Players, set 2)',
                     year='1981', manuf='Gremlin', parent='elim2'),
    'elim2c':   dict(id=0, name='Eliminator (2 Players, cocktail)',
                     year='1981', manuf='Gremlin', parent='elim2'),
    'elim4':    dict(id=1, name='Eliminator (4 Players)',
                     year='1981', manuf='Gremlin', parent='elim2'),
    'elim4p':   dict(id=1, name='Eliminator (4 Players, prototype)',
                     year='1981', manuf='Gremlin', parent='elim2'),
    'spacfury': dict(id=2, name='Space Fury (revision C)',
                     year='1981', manuf='Sega'),
    'spacfurya':dict(id=2, name='Space Fury (revision A)',
                     year='1981', manuf='Sega', parent='spacfury'),
    'zektor':   dict(id=3, name='Zektor (revision B)',
                     year='1982', manuf='Sega'),
    'tacscan':  dict(id=4, name='Tac/Scan',
                     year='1982', manuf='Sega'),
    'startrek': dict(id=5, name='Star Trek',
                     year='1982', manuf='Sega'),
}

PROG_END = 0xC000
IMAGE_END = 0xC400

COIN_IDS = ('4 Coins/1 Credit,3 Coins/1 Credit,2 Coins/1 Credit,'
            '1 Coin/1 Credit,1 Coin/2 Credits,1 Coin/3 Credits,'
            '1 Coin/4 Credits,1 Coin/5 Credits,1 Coin/6 Credits,'
            '2 Coins/1 Credit 5/3 6/4,2 Coins/1 Credit 4/3,'
            '1 Coin/1 Credit 5/6,1 Coin/1 Credit 4/5,'
            '1 Coin/1 Credit 2/3,1 Coin/2 Credits 5/11,'
            '1 Coin/2 Credits 4/9')


def switches_xml(meta):
    """MAME's two physical DIP banks, delivered to ioctl index 254."""
    game = meta['id']
    if game in (0, 1):
        sw1, sw2 = 0x45, (0x00 if game == 1 else 0x33)
    else:
        sw1, sw2 = 0x8D, 0x33

    dips = ['        <dip bits="0" ids="Cocktail,Upright" name="Cabinet"/>']
    if game >= 2:
        dips.append('        <dip bits="1" ids="On,Off" name="Demo Sounds"/>')

    if game in (0, 1):
        dips += [
            '        <dip bits="2,3" values="1,2,3" ids="3,4,5" name="Lives"/>',
            '        <dip bits="4,5" ids="Easy,Medium,Hard,Hardest" name="Difficulty"/>',
            '        <dip bits="6,7" ids="30000,20000,10000,None" name="Bonus Life"/>',
        ]
    elif game == 2:
        dips += [
            '        <dip bits="2,3" ids="2,3,4,5" name="Lives"/>',
            '        <dip bits="4,5" ids="Easy,Medium,Hard,Hardest" name="Difficulty"/>',
            '        <dip bits="6,7" ids="10000,20000,30000,40000" name="Bonus Life"/>',
        ]
    elif game == 3:
        dips += [
            '        <dip bits="2,3" ids="2,3,4,5" name="Lives"/>',
            '        <dip bits="4,5" ids="Easy,Medium,Hard,Hardest" name="Difficulty"/>',
            '        <dip bits="6,7" ids="None,30000,20000,10000" name="Bonus Life"/>',
        ]
    elif game == 4:
        dips += [
            '        <dip bits="2,3" ids="2,4,6,8" name="Ships"/>',
            '        <dip bits="4,5" ids="Easy,Normal,Hard,Very Hard" name="Difficulty"/>',
            '        <dip bits="6,7" ids="None,30000,20000,10000" name="Bonus Life"/>',
        ]
    else:
        dips += [
            '        <dip bits="2,3" ids="1,2,3,4" name="Photon Torpedoes"/>',
            '        <dip bits="4,5" ids="Easy,Medium,Hard,Tournament" name="Difficulty"/>',
            '        <dip bits="6,7" ids="10000,20000,30000,40000" name="Bonus Life"/>',
        ]

    if game == 1:
        dips.append('        <dip bits="13,14,15" ids="1 Coin/1 Credit,2 Coins/1 Credit,3 Coins/1 Credit,4 Coins/1 Credit,5 Coins/1 Credit,6 Coins/1 Credit,7 Coins/1 Credit,8 Coins/1 Credit" name="Coinage"/>')
    else:
        dips += [
            f'        <dip bits="8,9,10,11" ids="{COIN_IDS}" name="Coin A"/>',
            f'        <dip bits="12,13,14,15" ids="{COIN_IDS}" name="Coin B"/>',
        ]
    return (f'    <switches default="{sw1:02X},{sw2:02X}">\n' +
            '\n'.join(dips) + '\n    </switches>')


def buttons_xml(meta):
    if meta['id'] == 5:
        names = 'Fire,Fire 2,Fire 3,Fire 4,Start 1,Start 2,Coin,Pause'
        default = 'A,B,X,Y,Start,Select,R,L'
    else:
        # Keep the unused fire-3/fire-4 core slots explicit. MiSTer advances
        # the output slot for '-' without consuming a default-map entry.
        names = 'Fire,Thrust,-,-,Start 1,Start 2,Coin,Pause'
        default = 'A,B,Start,Select,R,L'
    return f'    <buttons names="{names}" default="{default}"/>'


def controls_xml(meta):
    players = 4 if meta['id'] == 1 else 2
    buttons = 4 if meta['id'] == 5 else 2
    if meta['id'] in (3, 4, 5):
        control = ('    <joystick></joystick>\n'
                   '    <special_controls>spinner</special_controls>')
    else:
        control = '    <joystick>2-way horizontal</joystick>'
    return (f'    <players>{players}</players>\n' + control + '\n' +
            f'    <num_buttons>{buttons}</num_buttons>')


def parse_sets(src_path):
    src = open(src_path).read()
    sets = {}
    for m in re.finditer(r'ROM_START\(\s*(\w+)\s*\)(.*?)ROM_END', src, re.S):
        name, body = m.groups()
        regions, cur = {}, None
        for line in body.splitlines():
            r = re.search(r'ROM_REGION\(\s*(0x[0-9a-fA-F]+)\s*,\s*"([^"]+)"', line)
            if r:
                cur = r.group(2)
                regions.setdefault(cur, [])
                continue
            l = re.search(r'ROM_LOAD\(\s*"([^"]+)"\s*,\s*(0x[0-9a-fA-F]+)\s*,'
                          r'\s*(0x[0-9a-fA-F]+)\s*,\s*CRC\(([0-9a-fA-F]+)\)', line)
            if l and cur:
                regions[cur].append(dict(name=l.group(1),
                                         offset=int(l.group(2), 16),
                                         size=int(l.group(3), 16),
                                         crc=l.group(4)))
        sets[name] = regions
    return sets


def emit(setname, regions, meta):
    prog = sorted(regions.get('maincpu', []), key=lambda p: p['offset'])
    sine = next((p for p in regions.get('proms', []) if 'xyt-u39' in p['name']),
                None)
    if not prog or sine is None:
        return None, 'missing maincpu or sine PROM'

    parts, pos = [], 0
    for p in prog:
        if p['offset'] < pos:
            return None, f"overlapping ROM at {p['name']}"
        if p['offset'] > pos:
            parts.append(f'        <part repeat="{p["offset"] - pos}">00</part>')
        parts.append(f'        <part name="{p["name"]}" crc="{p["crc"]}"/>')
        pos = p['offset'] + p['size']

    if pos > PROG_END:
        return None, 'program ROM overruns $C000'
    if pos < PROG_END:
        parts.append(f'        <part repeat="{PROG_END - pos}">00</part>')

    parts.append('        <!-- $C000: sin/cos PROM, X-Y Timing board U39 -->')
    parts.append(f'        <part name="{sine["name"]}" crc="{sine["crc"]}"/>')

    # $C400: speech board, only on Space Fury, Zektor and Star Trek
    def region(tag, base, size):
        items = sorted(regions.get(tag, []), key=lambda p: p['offset'])
        if not items:
            parts.append(f'        <part repeat="{size}">00</part>')
            return
        parts.append(f'        <!-- ${base:04X}: {tag} -->')
        pos = 0
        for it in items:
            if it['offset'] > pos:
                parts.append(f'        <part repeat="{it["offset"] - pos}">00</part>')
            parts.append(f'        <part name="{it["name"]}" crc="{it["crc"]}"/>')
            pos = it['offset'] + it['size']
        if pos < size:
            parts.append(f'        <part repeat="{size - pos}">00</part>')

    region('speech:cpu',  0xC400, 0x0800)
    region('speech:data', 0xCC00, 0x4000)

    rom_parts = '\n'.join(parts)
    parent = meta.get('parent', '')
    rbf = 'Arcade-SegaG80V'

    return f'''<misterromdescription>
    <about author="alanswx" webpage="https://github.com/alanswx/Arcade-SegaG80V_MiSTer"/>
    <name>{meta['name']}</name>
    <setname>{setname}</setname>
    <rbf>{rbf}</rbf>
    <mameversion>0283</mameversion>
    <year>{meta['year']}</year>
    <manufacturer>{meta['manuf']}</manufacturer>
    <category>Shooter</category>
{f'    <parent>{parent}</parent>' + chr(10) if parent else ''}\
{controls_xml(meta)}
    <!-- index 0: 48K program ROM at $0000, sin/cos PROM at $C000 -->
    <rom index="0" zip="{setname}.zip{('|' + parent + '.zip') if parent else ''}" md5="none">
{rom_parts}
    </rom>

    <!-- index 1: game identifier, decoded by rtl/sega_game_pkg.sv -->
    <rom index="1">
        <part>{meta['id']:02X}</part>
    </rom>

    <!-- Two physical DIP banks, delivered to ioctl index 254 by MiSTer. -->
{switches_xml(meta)}

{buttons_xml(meta)}
</misterromdescription>
''', None


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    src, outdir = sys.argv[1:3]
    wanted = sys.argv[3:]
    os.makedirs(outdir, exist_ok=True)

    sets = parse_sets(src)
    for name in (wanted or GAMES.keys()):
        if name not in GAMES:
            print(f'{name:12s} not a supported set')
            continue
        if name not in sets:
            print(f'{name:12s} not found in the driver')
            continue
        text, err = emit(name, sets[name], GAMES[name])
        if err:
            print(f'{name:12s} SKIP  {err}')
            continue
        # '/' in a title (Tac/Scan) is not usable in a filename
        fname = GAMES[name]['name'].replace('/', '-')
        path = os.path.join(outdir, f'{fname}.mra')
        open(path, 'w').write(text)
        print(f'{name:12s} -> {path}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
