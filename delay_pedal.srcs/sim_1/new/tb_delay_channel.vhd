----------------------------------------------------------------------------------
-- tb_delay_channel.vhd - сквозной тест одного канала (delay_channel)
-- Задержка эха i_delay = 81 отсчёт (линия задержки получает 81 - 65 = 16),
-- dry = 0,5 (128), wet = 1,0 (256), LP = HP = 1,0, обратная связь 0,5 (128).
-- Подаётся одиночный импульс 2^20. Ожидается:
--   событие 1:   прямой сигнал 0,5 * импульс (524288)
--   событие 81:  первое эхо ~ импульс (LPF + HPF = копия, задержанная на 81 отсчёт)
--   событие 162: второе эхо ~ 0,5 * импульс (обратная связь), расстояние = i_delay
--   далее: малые остатки (квантование коэффициентов) и затухающие повторы.
-- Эталон EXP (все 330 отсчётов) посчитан побитовой моделью (те же .coe, сдвиги, насыщение).
-- Нужны IP: fifo_delay_axis, fir_lpf_129t_b16, fir_hpf_129t_b16.
-- Время симуляции: около 0,55 мс модельного времени (несколько минут реального).
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_delay_channel is
end tb_delay_channel;

architecture sim of tb_delay_channel is
  constant A            : integer := 1048576;   -- амплитуда импульса 2^20
  constant N_EVENTS     : natural := 330;
  constant CLK_PER_SMPL : natural := 200;
  constant TOL          : integer := 2;

  type int_arr is array (0 to 329) of integer;
  constant EXP : int_arr := (
    524288, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 4, 4, 8, 12,
    16, -12, -4, 0, 4, 4, 0, 12, 16, 0,
    -4, 8, 8, 8, -12, 0, 4, -4, 0, 4,
    4, -4, -4, 12, 12, -8, 12, -8, -5, -5,
    -1, -1, 11, 11, -1, 3, -13, -5, 3, 7,
    7, 11, 7, -17, 7, 11, 7, 7, 15, 3,
    1048575, 3, 15, 7, 7, 11, 7, -17, 7, 11,
    7, 7, 3, -5, -13, 3, -1, 11, 11, -1,
    -1, -5, -5, -9, 11, -9, 11, 15, -1, 3,
    15, 19, -13, -9, 3, 3, -9, 7, 19, 23,
    -5, -5, 23, 19, 7, -9, 3, 3, -9, -13,
    19, 15, 3, -1, 15, 11, -9, 11, -9, -6,
    -6, -2, -2, 10, 10, -2, 2, -14, -6, 2,
    6, 6, 10, 6, -18, 6, 10, 6, 6, 14,
    2, 524286, 2, 14, 6, 6, 10, 6, -18, 6,
    10, 6, 6, 2, -6, -14, 2, -2, 10, 10,
    -2, -2, -6, -6, -10, 10, -10, 10, 13, -3,
    0, 11, 14, -11, -9, 2, 1, -11, 6, 15,
    18, -6, -5, 20, 16, 4, -7, 2, 1, -9,
    -14, 17, 13, 3, -1, 11, 7, -8, 7, -8,
    -5, -5, -2, -2, 7, 7, -2, 1, -11, -5,
    1, 4, 4, 7, 4, -14, 4, 7, 4, 4,
    10, 1, 262142, 1, 10, 4, 4, 7, 4, -14,
    4, 7, 4, 4, 1, -5, -11, 1, -2, 7,
    7, -2, -2, -5, -5, -8, 7, -8, 7, 8,
    -4, -1, 7, 9, -8, -7, 1, -1, -10, 4,
    10, 12, -5, -4, 14, 11, 2, -5, 1, -1,
    -8, -11, 12, 9, 2, -2, 6, 3, -6, 4,
    -6, -4, -5, -2, -2, 3, 3, -2, -1, -9,
    -4, 0, 2, 2, 3, 2, -10, 2, 3, 2,
    2, 6, 0, 131070, 0, 6, 2, 2, 3, 2
  );

  signal clk      : std_logic := '0';
  signal finished : std_logic := '0';
  signal rst      : std_logic := '1';
  signal val      : std_logic := '0';
  signal dat      : std_logic_vector(23 downto 0) := (others => '0');
  signal o_val    : std_logic;
  signal o_dat    : std_logic_vector(23 downto 0);
  signal n_out    : natural := 0;
  signal errors   : natural := 0;
begin

  clk_gen : process
  begin
    while finished = '0' loop
      clk <= '0'; wait for 5 ns;
      clk <= '1'; wait for 5 ns;
    end loop;
    wait;
  end process;

  dut : entity work.delay_channel
    port map (
      i_clk      => clk,
      i_rst      => rst,
      i_flush    => '0',
      i_val      => val,
      i_dat      => dat,
      i_delay    => std_logic_vector(to_unsigned(81, 16)),
      i_gain_dry => std_logic_vector(to_unsigned(128, 9)),
      i_gain_wet => std_logic_vector(to_unsigned(256, 9)),
      i_gain_lp  => std_logic_vector(to_unsigned(256, 9)),
      i_gain_hp  => std_logic_vector(to_unsigned(256, 9)),
      i_gain_fb  => std_logic_vector(to_unsigned(128, 9)),
      o_val      => o_val,
      o_dat      => o_dat);

  stim : process
  begin
    rst <= '1';
    for i in 1 to 20 loop wait until rising_edge(clk); end loop;
    rst <= '0';
    for i in 1 to 20 loop wait until rising_edge(clk); end loop;

    for k in 1 to N_EVENTS loop
      wait until rising_edge(clk);
      if k = 1 then
        dat <= std_logic_vector(to_signed(A, 24));
      else
        dat <= (others => '0');
      end if;
      val <= '1';
      wait until rising_edge(clk);
      val <= '0';
      for j in 1 to CLK_PER_SMPL loop wait until rising_edge(clk); end loop;
    end loop;

    for j in 1 to 300 loop wait until rising_edge(clk); end loop;

    report "outputs checked: " & integer'image(n_out) severity note;
    if errors = 0 and n_out = N_EVENTS then
      report "TEST PASSED: delay_channel (delay + LPF + HPF + mix + feedback) OK" severity note;
    else
      report "TEST FAILED: " & integer'image(errors) & " mismatches, outputs = " &
             integer'image(n_out) severity error;
    end if;
    finished <= '1';
    wait;
  end process;

  check : process(clk)
    variable e     : natural;
    variable exp_v : integer;
  begin
    if rising_edge(clk) then
      if o_val = '1' then
        e := n_out + 1;
        n_out <= e;
        if e <= N_EVENTS then
          exp_v := EXP(e - 1);
        else
          exp_v := 0;
        end if;
        if abs(to_integer(signed(o_dat)) - exp_v) > TOL then
          errors <= errors + 1;
          report "Mismatch at output " & integer'image(e) & ": got " &
                 integer'image(to_integer(signed(o_dat))) & ", expected " &
                 integer'image(exp_v) severity error;
        end if;
      end if;
    end if;
  end process;

end sim;