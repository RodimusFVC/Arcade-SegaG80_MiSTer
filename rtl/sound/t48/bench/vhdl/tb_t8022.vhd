-------------------------------------------------------------------------------
--
-- The testbench for t8022.
--
-- Copyright (c) 2004-2023, Arnim Laeuger (arniml@opencores.org)
--
-- All rights reserved
--
-- Redistribution and use in source and synthezised forms, with or without
-- modification, are permitted provided that the following conditions are met:
--
-- Redistributions of source code must retain the above copyright notice,
-- this list of conditions and the following disclaimer.
--
-- Redistributions in synthesized form must reproduce the above copyright
-- notice, this list of conditions and the following disclaimer in the
-- documentation and/or other materials provided with the distribution.
--
-- Neither the name of the author nor the names of other contributors may
-- be used to endorse or promote products derived from this software without
-- specific prior written permission.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
-- AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
-- THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
-- PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
-- LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
-- CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
-- SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
-- INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
-- CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
-- ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
-- POSSIBILITY OF SUCH DAMAGE.
--
-- Please report bugs to the author, but before you do so, please
-- make sure that this is not a derivative work and that
-- you have the latest version of this file.
--
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity tb_t8022 is

end tb_t8022;


use work.t48_tb_pack.all;

architecture behav of tb_t8022 is

  -- clock period, 11 MHz
  constant period_c : time := 90 ns;

  component lpm_rom
    generic (
      LPM_WIDTH           : positive;
      LPM_TYPE            : string    := "LPM_ROM";
      LPM_WIDTHAD         : positive;
      LPM_NUMWORDS        : natural   := 0;
      LPM_FILE            : string;
      LPM_ADDRESS_CONTROL : string    := "REGISTERED";
      LPM_OUTDATA         : string    := "REGISTERED";
      LPM_HINT            : string    := "UNUSED"
    );
    port (
      address             : in  std_logic_vector(LPM_WIDTHAD-1 downto 0);
      inclock             : in  std_logic;
      outclock            : in  std_logic;
      memenab             : in  std_logic;
      q                   : out std_logic_vector(LPM_WIDTH-1 downto 0)
    );
  end component;

  signal xtal_s          : std_logic;
  signal res_s           : std_logic;
  signal ale_s           : std_logic;
  signal prog_n_s        : std_logic;

  signal p0_b : std_logic_vector( 7 downto 0);
  signal p1_b : std_logic_vector( 7 downto 0);
  signal p2_b : std_logic_vector( 7 downto 0);

  signal an0_s : std_logic_vector( 7 downto 0);
  signal an1_s : std_logic_vector( 7 downto 0);

begin

  p2_b   <= (others => 'H');
  p1_b   <= (others => 'H');
  p0_b   <= (others => 'H');

  an0_s <= "01101001";
  an1_s <= "10010110";

  t8022_b : entity work.t8022
    port map (
      xtal_i    => xtal_s,
      reset_i   => res_s,
      ale_o     => ale_s,
      t0_i      => p1_b(0),
      t1_i      => p1_b(1),
      p2_b      => p2_b,
      p1_b      => p1_b,
      p0_b      => p0_b,
      prog_n_o  => prog_n_s,
      an0_i     => an0_s,
      an1_i     => an1_s
    );


  -----------------------------------------------------------------------------
  -- The clock generator
  --
  clk_gen: process
  begin
    xtal_s <= '0';
    wait for period_c/2;
    xtal_s <= '1';
    wait for period_c/2;
  end process clk_gen;
  --
  -----------------------------------------------------------------------------


  -----------------------------------------------------------------------------
  -- The reset generator
  --
  res_gen: process
  begin
    res_s <= '1';
    wait for 5 * period_c;
    res_s <= '0';
    wait;
  end process res_gen;
  --
  -----------------------------------------------------------------------------


  -----------------------------------------------------------------------------
  -- End of simulation detection
  --
  eos: process
  begin

    outer: loop
      wait on tb_accu_s;
      if tb_accu_s = "10101010" then
        wait on tb_accu_s;
        if tb_accu_s = "01010101" then
          wait on tb_accu_s;
          if tb_accu_s = "00000001" then
            -- wait for instruction strobe of this move
            wait until tb_istrobe_s'event and tb_istrobe_s = '1';
            -- wait for next strobe
            wait until tb_istrobe_s'event and tb_istrobe_s = '1';
            assert false
              report "Simulation Result: PASS."
              severity note;
          else
            assert false
              report "Simulation Result: FAIL."
              severity note;
          end if;

          assert false
            report "End of simulation reached."
            severity failure;

        end if;
      end if;
    end loop;

  end process eos;
  --
  -----------------------------------------------------------------------------

end behav;
