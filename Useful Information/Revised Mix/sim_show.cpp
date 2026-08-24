// Full-roster showcase at TRUE mixer levels (OUTPUT_GAIN_LOG2 = 2 output),
// one dump; segments separated by 0.4 s of silence.
#include "Vastrob_audio.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
static Vastrob_audio *dut; static FILE *fh;
static long acc=0; static int dc=0;
static void tick(){
    dut->clk_sys=0;dut->eval();dut->clk_sys=1;dut->eval();
    acc+=(int16_t)dut->audio_out;
    if(++dc==128){fprintf(fh,"%ld\n",acc);acc=0;dc=0;}
}
static void wr(int a,uint8_t d){dut->audio_addr=a;dut->audio_din=d;dut->audio_we=1;tick();dut->audio_we=0;tick();}
static void run_s(double s){long n=(long)(s*15468480.0);for(long i=0;i<n;i++)tick();}
// idle bytes: unmuted, warp bit CLEAR (drive it explicitly per segment)
static uint8_t LO_IDLE=0xFF&~(1u<<5)&~(1u<<7), HI_IDLE=0xFF;
static void idle(){wr(0,LO_IDLE);wr(1,HI_IDLE);}
int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);
    dut=new Vastrob_audio;
    fh=fopen("show.txt","w");
    dut->clk_sys=0;dut->reset=1;dut->audio_we=0;dut->audio_addr=0;dut->audio_din=0xFF;dut->ce_cpu=1;
    for(int i=0;i<20;i++)tick();          // CLOCKED reset (unclocked eval()
                                           // left the LFSR zero-locked)
    dut->reset=0; idle(); run_s(0.2);

    // ---- invader marches: 1.5 s at step 0, then release the attack
    //      staircase for 1.5 s so the climb is a distinct event ----
    for(int v=0;v<4;v++){
        wr(1,(HI_IDLE&~(1u<<5))&~(1u<<4)); wr(1,HI_IDLE&~(1u<<4)); // reset->step0, bit4 LOW = frozen
        wr(0,LO_IDLE&~(1u<<v));                     // march on, staircase FROZEN
        run_s(1.5);
        wr(1,HI_IDLE);                              // bit4 HIGH: staircase climbs
        run_s(1.5);
        idle(); run_s(0.4);
    }
    // all four together: same shape
    wr(1,(HI_IDLE&~(1u<<5))&~(1u<<4)); wr(1,HI_IDLE&~(1u<<4));
    wr(0,LO_IDLE&~0x0F); run_s(1.5);
    wr(1,HI_IDLE); run_s(1.5); idle(); run_s(0.4);
    // all four + WARP (bit7 high), held at step 0 for a clean A/B
    wr(1,(HI_IDLE&~(1u<<5))&~(1u<<4)); wr(1,HI_IDLE&~(1u<<4));
    wr(0,(LO_IDLE&~0x0F)|0x80); run_s(3.0); idle(); run_s(0.4);

    // ---- one-shots: 3 shots each for lasers, 2 for explosions ----
    for(int b=0;b<2;b++){ for(int k=0;k<3;k++){ wr(1,HI_IDLE&~(1u<<b)); wr(1,HI_IDLE); run_s(0.45);} run_s(0.5); idle(); run_s(0.4);}
    for(int b=2;b<4;b++){ for(int k=0;k<2;k++){ wr(1,HI_IDLE&~(1u<<b)); wr(1,HI_IDLE); run_s(b==2?0.5:0.7);} run_s(0.4); idle(); run_s(0.4);}

    // ---- level voices ----
    wr(0,LO_IDLE&~(1u<<4)); run_s(2.0); idle(); run_s(0.4);       // asteroids
    wr(0,LO_IDLE&~(1u<<6)); run_s(4.0); idle(); run_s(0.4);       // refill

    // ---- sonar, bonus ----
    wr(1,HI_IDLE&~(1u<<7)); wr(1,HI_IDLE); run_s(1.5); idle(); run_s(0.4);
    wr(1,HI_IDLE&~(1u<<6)); wr(1,HI_IDLE); run_s(3.5); idle(); run_s(0.4);

    // ---- the wave-launch combo: lasers 1+2 + sonar in one write ----
    wr(1,HI_IDLE&~0x83); wr(1,HI_IDLE); run_s(1.5);
    idle(); run_s(0.2);
    fclose(fh); fprintf(stderr,"done\n"); return 0;
}
