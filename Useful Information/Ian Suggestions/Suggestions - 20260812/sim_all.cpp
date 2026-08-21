// Renders: laser1, laser2, short_expl, long_expl, asteroids, refill.
#include "Vastrob_audio.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <cstring>

static Vastrob_audio *dut;
static void tick(){ dut->clk_sys=0; dut->eval(); dut->clk_sys=1; dut->eval(); }
static void wr(int a, uint8_t d){
    dut->audio_addr=a; dut->audio_din=d; dut->audio_we=1; tick();
    dut->audio_we=0; tick();
}

// each entry: name, port(0=$3E,1=$3F), bit, mode: 0=level-hold, 1=edge-trigger
struct V { const char* n; int port; int bit; int mode; };
static V voices[] = {
    {"laser1",   1, 0, 1},
    {"laser2",   1, 1, 1},
    {"sexpl",    1, 2, 1},
    {"lexpl",    1, 3, 1},
    {"astro",    0, 4, 0},
    {"refill",   0, 6, 0},
    {"sonar",    1, 7, 1},
    {"bonus",    1, 6, 1},
};

int main(int argc, char **argv){
    Verilated::commandArgs(argc, argv);
    const int  DECIM = 128;
    const long NSAMP = atol(argv[1]);

    dut = new Vastrob_audio;
    dut->clk_sys=0; dut->reset=1; dut->audio_we=0;
    dut->audio_addr=0; dut->audio_din=0xFF; dut->ce_cpu=1;
    for (int i=0;i<20;i++) tick();
    dut->reset=0;
    for (int i=0;i<20;i++) tick();

    for (auto &v : voices){
        char fn[32]; snprintf(fn,sizeof fn,"%s.txt", v.n);
        FILE *fh=fopen(fn,"w");

        // idle both ports, unmuted on $3E bit5
        uint8_t lo=0xFF & ~(1u<<5);
        uint8_t hi=0xFF;
        wr(0,lo); wr(1,hi);
        for (int i=0;i<50000;i++) tick();

        // assert the voice bit (low). For edge voices we re-trigger every
        // 400 ms to show the retrigger path; for level voices hold it.
        long acc=0,n=0; int cnt=0; long clk_in_seg=0;
        long RETRIG = 6187392;   // 400 ms in clks
        if (!strcmp(v.n,"sonar")) RETRIG = 15468480;      // 1 s
        if (!strcmp(v.n,"bonus")) RETRIG = 61873920;      // 4 s
        uint8_t *reg = v.port ? &hi : &lo;
        *reg &= ~(1u<<v.bit);
        wr(v.port, *reg);
        if (v.mode==1){ *reg |= (1u<<v.bit); wr(v.port, *reg); } // release: edge done

        while (n<NSAMP){
            tick(); clk_in_seg++;
            if (v.mode==1 && clk_in_seg % RETRIG == 0){
                *reg &= ~(1u<<v.bit); wr(v.port,*reg);
                *reg |=  (1u<<v.bit); wr(v.port,*reg);
            }
            acc += (int16_t)dut->audio_out;
            if (++cnt==DECIM){ fprintf(fh,"%ld\n",acc); acc=0; cnt=0; n++; }
        }
        fclose(fh);
        // voice off
        *reg |= (1u<<v.bit); wr(v.port,*reg);
        fprintf(stderr,"rendered %s\n",fn);
        for (int i=0;i<15468480;i++) tick();  // 1 s: let envelopes die
    }
    fprintf(stderr,"ALL DONE\n");
    delete dut; return 0;
}
