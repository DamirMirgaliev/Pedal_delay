----------------------------------------------------------------------------------
-- tb_delay_channel.vhd - сквозной тест одного канала эффекта (delay_channel)
-- Подаётся одиночный импульс 2^20. Задержка D = 16 отсчётов, dry = 0, LPF = HPF = 1.0.
-- Так как HPF построен как "единица минус LPF", сумма LPF + HPF даёт копию импульса,
-- задержанную на D + 64 отсчёта (64 = задержка линейно-фазового FIR). Остальные
-- отсчёты - небольшие остатки квантования коэффициентов 16 бит.
-- Эталон (массив EXP) посчитан целочисленной моделью (те же .coe, сдвиги 18 и 15).
-- Номер выходного события E = D + 1 + j, j = 0..128 (j = номер коэффициента).
-- Нужны IP: fifo_delay_axis, fir_lpf_129t_b16, fir_hpf_129t_b16.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_delay_channel is
end tb_delay_channel;

architecture sim of tb_delay_channel is
  constant D            : natural := 16;
  constant A            : integer := 1048576;   -- амплитуда импульса 2^20
  constant N_EVENTS     : natural := 200;
  constant CLK_PER_SMPL : natural := 160;
  constant TOL          : integer := 2;

  type int_arr is array (0 to 128) of integer;
  constant EXP : int_arr := (
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 4, 4, 8, 12, 16, -12,
    -4, 0, 4, 4, 0, 12, 16, 0,
    -4, 8, 8, 8, -12, 0, 4, -4,
    0, 4, 4, -4, -4, 12, 12, -8,
    12, -8, -4, -4, 0, 0, 12, 12,
    0, 4, -12, -4, 4, 8, 8, 12,
    8, -16, 8, 12, 8, 8, 16, 4,
    1048576, 4, 16, 8, 8, 12, 8, -16,
    8, 12, 8, 8, 4, -4, -12, 4,
    0, 12, 12, 0, 0, -4, -4, -8,
    12, -8, 12, 12, -4, -4, 4, 4,
    0, -4, 4, 0, -12, 8, 8, 8,
    -4, 0, 16, 12, 0, 4, 4, 0,
    -4, -12, 16, 12, 8, 4, 4, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0
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
      i_val      => val,
      i_dat      => dat,
      i_enable   => '1',
      i_delay    => std_logic_vector(to_unsigned(D, 16)),
      i_gain_dry => std_logic_vector(to_unsigned(0, 9)),
      i_gain_lp  => std_logic_vector(to_unsigned(256, 9)),
      i_gain_hp  => std_logic_vector(to_unsigned(256, 9)),
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
      report "TEST PASSED: delay_channel (delay + LPF + HPF + mix) OK" severity note;
    else
      report "TEST FAILED: " & integer'image(errors) & " mismatches, outputs = " &
             integer'image(n_out) severity error;
    end if;
    finished <= '1';
    wait;
  end process;

  check : process(clk)
    variable e   : natural;
    variable exp_v : integer;
  begin
    if rising_edge(clk) then
      if o_val = '1' then
        e := n_out + 1;
        n_out <= e;
        if e >= D + 1 and e <= D + 1 + 128 then
          exp_v := EXP(e - D - 1);
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