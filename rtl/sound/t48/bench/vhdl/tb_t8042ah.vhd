-------------------------------------------------------------------------------
--
-- The testbench for t8042ah.
--
-- Copyright (c) 2004-2022, Arnim Laeuger (arniml@opencores.org)
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

entity tb_t8042ah is

end tb_t8042ah;


use work.t48_tb_pack.all;

architecture behav of tb_t8042ah is

  -- clock period, 11 MHz
  constant period_c : time := 90 ns;

  signal xtal_s          : std_logic;
  signal res_n_s         : std_logic;
  signal prog_n_s        : std_logic;

  signal p1_b : std_logic_vector( 7 downto 0);
  signal p2_b : std_logic_vector( 7 downto 0);

  signal db_b   : std_logic_vector( 7 downto 0);
  signal cs_n_s : std_logic;
  signal rd_n_s : std_logic;
  signal wr_n_s : std_logic;
  signal a0_s   : std_logic;

  signal fail_s : boolean;

begin

  p2_b   <= (others => 'H');
  p1_b   <= (others => 'H');

  t8042ah_b : entity work.t8042ah
    port map (
      xtal_i    => xtal_s,
      reset_n_i => res_n_s,
      cs_n_i    => cs_n_s,
      rd_n_i    => rd_n_s,
      a0_i      => a0_s,
      wr_n_i    => wr_n_s,
      t0_i      => p1_b(0),
      db_b      => db_b,
      t1_i      => p1_b(1),
      p2_b      => p2_b,
      p1_b      => p1_b,
      prog_n_o  => prog_n_s
    );


  -----------------------------------------------------------------------------
  -- Generic UPI stimulus generator
  --
  upi_stim_b: entity work.upi_stim
    port map (
      cs_n_o => cs_n_s,
      rd_n_o => rd_n_s,
      wr_n_o => wr_n_s,
      a0_o   => a0_s,
      db_b   => db_b,
      p1_b   => p1_b,
      p2_b   => p2_b,
      fail_o => fail_s
    );
  --
  -----------------------------------------------------------------------------


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
    res_n_s <= '0';
    wait for 5 * period_c;
    res_n_s <= '1';
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

            if not fail_s then
              assert false
                report "Simulation Result: PASS."
                severity note;
            else
              assert false
                report "Simulation Result: FAIL from TB."
                severity note;
            end if;
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
