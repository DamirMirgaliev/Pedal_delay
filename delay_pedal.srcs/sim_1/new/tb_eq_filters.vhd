----------------------------------------------------------------------------------
-- tb_eq_filters.vhd - проверка ј„’ eq_lpf и eq_hpf синусами
-- ѕодаютс€ синусы 400 √ц, 1 к√ц, 2,4 к√ц и 6 к√ц амплитудой 2^22 (половина шкалы 24 бит),
-- измер€етс€ амплитуда на выходе и сравниваетс€ с эталоном. Ёталон посчитан
-- побитово-точной целочисленной моделью (те же .coe 16 бит, сдвиг и насыщение),
-- допуск +-64 LSB.
-- ќжидаемые коэффициенты передачи:
--   400 √ц:  LPF  0,0 дЅ   HPF -85,3 дЅ
--   1 к√ц:   LPF -0,0 дЅ   HPF -56,1 дЅ
--   2,4 к√ц: LPF -6,9 дЅ   HPF  -5,2 дЅ
--   6 к√ц:   LPF -91,6 дЅ  HPF  -0,0 дЅ
-- “естбенч сам останавливает тактовый генератор по окончании, поэтому "run all"
-- завершаетс€ сам. ¬рем€ теста около 1,7 мс модельного времени.
-- ƒобавить как Simulation Source (нужны IP fir_lpf_129t_b16 и fir_hpf_129t_b16).
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

entity tb_eq_filters is
end tb_eq_filters;

architecture sim of tb_eq_filters is
  constant A            : integer := 4194304;   -- амплитуда 2^22
  constant CLK_PER_SMPL : natural := 160;       -- в симул€ции период сокращЄн (в железе ~2083); > 137 тактов задержки IP
  constant SETTLE       : natural := 140;       -- отсчЄтов на установление (> 129)
  constant TOL          : integer := 64;

  type int_arr is array (0 to 3) of integer;
  constant N_PER   : int_arr := (120, 48, 20, 8);                     -- отсчЄтов на период
  constant WINDOW  : int_arr := (240, 96, 100, 96);                   -- окно измерени€, отсчЄтов (>= 1 период)
  constant EXP_LPF : int_arr := (4194286, 4188378, 1900207, 110);
  constant EXP_HPF : int_arr := (227, 6599, 2294142, 4194070);

  signal clk      : std_logic := '0';
  signal finished : std_logic := '0';
  signal val      : std_logic := '0';
  signal dat      : std_logic_vector(23 downto 0) := (others => '0');
  signal l_val    : std_logic;
  signal h_val    : std_logic;
  signal l_dat    : std_logic_vector(23 downto 0);
  signal h_dat    : std_logic_vector(23 downto 0);
  signal pk_l     : integer := 0;
  signal pk_h     : integer := 0;
  signal meas     : std_logic := '0';
begin

  -- тактовый генератор 100 ћ√ц, останавливаетс€ по окончании теста
  clk_gen : process
  begin
    while finished = '0' loop
      clk <= '0'; wait for 5 ns;
      clk <= '1'; wait for 5 ns;
    end loop;
    wait;
  end process;

  dut_l : entity work.eq_lpf
    generic map (SHIFT => 18, OUT_W => 43)
    port map (i_clk => clk, i_val => val, i_dat => dat, o_val => l_val, o_dat => l_dat);

  dut_h : entity work.eq_hpf
    generic map (SHIFT => 15, OUT_W => 41)
    port map (i_clk => clk, i_val => val, i_dat => dat, o_val => h_val, o_dat => h_dat);

  -- измерение пиковой амплитуды на выходах в окне meas = '1'
  mon : process(clk)
  begin
    if rising_edge(clk) then
      if meas = '0' then
        pk_l <= 0;
        pk_h <= 0;
      else
        if l_val = '1' and abs(to_integer(signed(l_dat))) > pk_l then
          pk_l <= abs(to_integer(signed(l_dat)));
        end if;
        if h_val = '1' and abs(to_integer(signed(h_dat))) > pk_h then
          pk_h <= abs(to_integer(signed(h_dat)));
        end if;
      end if;
    end if;
  end process;

  stim : process
    variable n      : integer;
    variable x      : integer;
    variable errors : natural := 0;
  begin
    for i in 1 to 20 loop wait until rising_edge(clk); end loop;

    for t in 0 to 3 loop
      n := N_PER(t);
      report "Testing " & integer'image(48000 / n) & " Hz ..." severity note;

      for k in 0 to SETTLE + WINDOW(t) - 1 loop
        wait until rising_edge(clk);
        x := integer(round(real(A) * sin(2.0 * MATH_PI * real(k) / real(n))));
        dat <= std_logic_vector(to_signed(x, 24));
        val <= '1';
        if k = SETTLE then meas <= '1'; end if;
        wait until rising_edge(clk);
        val <= '0';
        for j in 1 to CLK_PER_SMPL loop wait until rising_edge(clk); end loop;
      end loop;

      for j in 1 to 300 loop wait until rising_edge(clk); end loop;   -- дождатьс€ последнего выхода

      report integer'image(48000 / n) & " Hz:  LPF peak = " & integer'image(pk_l) &
             " (expected " & integer'image(EXP_LPF(t)) & "),  HPF peak = " & integer'image(pk_h) &
             " (expected " & integer'image(EXP_HPF(t)) & ")" severity note;

      if abs(pk_l - EXP_LPF(t)) > TOL then
        errors := errors + 1;
        report "LPF mismatch at " & integer'image(48000 / n) & " Hz" severity error;
      end if;
      if abs(pk_h - EXP_HPF(t)) > TOL then
        errors := errors + 1;
        report "HPF mismatch at " & integer'image(48000 / n) & " Hz" severity error;
      end if;

      meas <= '0';
      for j in 1 to 5 loop wait until rising_edge(clk); end loop;
    end loop;

    if errors = 0 then
      report "TEST PASSED: eq_lpf and eq_hpf frequency response OK" severity note;
    else
      report "TEST FAILED: " & integer'image(errors) & " mismatches" severity error;
    end if;

    finished <= '1';   -- остановить тактовый генератор -> симул€ци€ завершаетс€ сама
    wait;
  end process;

end sim;