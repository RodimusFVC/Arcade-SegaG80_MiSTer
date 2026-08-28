// Phase 0 colour census.
//
// Walks real vector-RAM snapshots (dumped from MAME by tools/dump_vram.lua)
// with the golden model and reports which of the 64 attribute colours the games
// actually emit.
//
// This decides whether videodr0me_fb's colour path has to be widened. The
// renderer stores 3-bit RGB plus an 8-bit Z intensity per pixel, so a Sega
// colour is representable unchanged only if all of its non-zero channels sit at
// the same level (hue x brightness). A colour like R=3 G=1 B=0 is not.

#include <cstdio>
#include <cstdint>
#include <cstring>
#include <map>
#include <set>
#include <string>
#include <vector>
#include <dirent.h>

#include "segag80v_golden.h"

static bool read_file(const std::string &path, uint8_t *buf, size_t n) {
	FILE *f = fopen(path.c_str(), "rb");
	if (!f) return false;
	size_t got = fread(buf, 1, n, f);
	fclose(f);
	return got == n;
}

static std::vector<std::string> list_dir(const std::string &dir) {
	std::vector<std::string> out;
	DIR *d = opendir(dir.c_str());
	if (!d) return out;
	while (struct dirent *e = readdir(d)) {
		std::string n = e->d_name;
		if (n.size() > 4 && n.substr(n.size() - 4) == ".bin")
			out.push_back(dir + "/" + n);
	}
	closedir(d);
	return out;
}

// colour is RRGGBB: R = bits[5:4], G = bits[3:2], B = bits[1:0]
static bool representable(uint8_t c) {
	int r = (c >> 4) & 3, g = (c >> 2) & 3, b = c & 3;
	int lvl = 0;
	for (int v : {r, g, b}) if (v) { if (!lvl) lvl = v; else if (v != lvl) return false; }
	return true;
}

int main(int argc, char **argv) {
	if (argc < 3) {
		printf("usage: census <sine-prom> <dumpdir> [dumpdir...]\n");
		return 2;
	}

	uint8_t sintab[1024];
	if (!read_file(argv[1], sintab, sizeof sintab)) {
		printf("cannot read sine PROM %s\n", argv[1]);
		return 2;
	}

	XyConfig cfg;
	std::map<uint8_t, long> global_hist;
	std::set<uint8_t> global_bad;
	long global_samples = 0;

	printf("%-10s %8s %10s %7s %7s  %s\n",
	       "game", "frames", "beam-on", "colours", "unrepr", "colours used (RRGGBB hex)");

	for (int a = 2; a < argc; a++) {
		std::string dir = argv[a];
		std::string game = dir.substr(dir.find_last_of('/') + 1);
		auto files = list_dir(dir);
		if (files.empty()) continue;

		std::map<uint8_t, long> hist;
		long beam_on = 0;
		uint8_t vram[4096];

		for (auto &f : files) {
			if (!read_file(f, vram, sizeof vram)) continue;
			std::vector<VecSample> out;
			sega_xy_golden(vram, sintab, cfg, out);
			for (auto &s : out) {
				if (!s.beam) continue;
				beam_on++;
				hist[s.colour]++;
			}
		}

		std::set<uint8_t> bad;
		std::string list;
		for (auto &kv : hist) {
			char b[8];
			snprintf(b, sizeof b, "%02X ", kv.first);
			list += b;
			if (!representable(kv.first)) { bad.insert(kv.first); global_bad.insert(kv.first); }
			global_hist[kv.first] += kv.second;
		}
		global_samples += beam_on;

		printf("%-10s %8zu %10ld %7zu %7zu  %s\n",
		       game.c_str(), files.size(), beam_on, hist.size(), bad.size(), list.c_str());
	}

	printf("\n--- combined ---\n");
	printf("%ld beam-on samples, %zu distinct colours of 64\n",
	       global_samples, global_hist.size());

	printf("\ncolour   R G B   share      representable as hue x brightness?\n");
	for (auto &kv : global_hist) {
		uint8_t c = kv.first;
		double pct = global_samples ? 100.0 * kv.second / global_samples : 0.0;
		printf("  %02X     %d %d %d   %6.2f%%    %s\n",
		       c, (c >> 4) & 3, (c >> 2) & 3, c & 3, pct,
		       representable(c) ? "yes" : "NO");
	}

	printf("\nVERDICT: ");
	if (global_bad.empty())
		printf("all %zu colours map onto 3-bit hue + Z brightness — "
		       "videodr0me_fb needs NO change.\n", global_hist.size());
	else {
		long badn = 0;
		for (auto &kv : global_hist) if (global_bad.count(kv.first)) badn += kv.second;
		printf("%zu colours (%.2f%% of beam-on samples) need true 6-bit colour — "
		       "the renderer repack IS required.\n",
		       global_bad.size(), global_samples ? 100.0 * badn / global_samples : 0.0);
	}
	return 0;
}
