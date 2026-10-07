----------------------------------------------------------------------------------
-- tb_pot_ctrl.vhd - проверка обработки потенциометров (усреднение, гистерезис, законы)
-- Быстрый тест (чистая логика, без IP). В каждый канал подаётся базовый код с шумом +-2:
--   канал 0 (задержка) = 0     -> 73 отсчёта (минимум)
--   канал 1 (микс)     = 4095  -> 256
--   канал 2 (НЧ)       = 2048  -> линейно 128, квадратичный закон -> 64
--   канал 3 (ВЧ)       = 4095  -> 256
--   обратная связь (потенциометра нет) = FB_DEFAULT = 0
-- Затем канал 0 переводится на 2048: задержка должна стать около 73 + 15996 = 16069.
-- Затем на канал 2 подаётся 2050 (в пределах гистерезиса 3) - выход не должен измениться.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_pot_ctrl is
end tb_pot_ctrl;

architecture sim of tb_pot_ctrl is
  signal clk      : std_logic := '0';
  signal finished : std_logic := '0';
  signal valid    : std_logic := '0';
  signal chan     : std_logic_vector(2 downto 0) := (others => '0');
  signal code     : std_logic_vector(11 downto 0) := (others => '0');
  signal o_delay  : std_logic_vector(15 downto 0);
  signal o_mix, o_lp, o_hp, o_fb : std_logic_vector(8 downto 0);
begin

  clk_gen : process
  begin
    while finished = '0' loop
      clk <= '0'; wait for 5 ns;
      clk <= '1'; wait for 5 ns;
    end loop;
    wait;
  end process;

  dut : entity work.pot_ctrl
    generic map (NUM_POTS => 4)
    port map (i_clk => clk, i_rst => '0', i_valid => valid, i_chan => chan, i_code => code,
              o_delay => o_delay, o_mix => o_mix, o_lp => o_lp, o_hp => o_hp, o_fb => o_fb);

  stim : process
    type base_t is array (0 to 3) of integer;
    variable base   : base_t := (0, 4095, 2048, 4095);
    variable errors : natural := 0;
    variable c      : integer;
    variable noise  : integer;

    -- одна передача кодов по всем четырём каналам, "rounds" раз
    procedure send(rounds : natural) is
    begin
      for r in 0 to rounds - 1 loop
        for ch in 0 to 3 loop
          noise := ((r + ch) mod 5) - 2;                 -- -2..+2
          c := base(ch) + noise;
          if c < 0 then c := 0; end if;
          if c > 4095 then c := 4095; end if;
          wait until rising_edge(clk);
          chan  <= std_logic_vector(to_unsigned(ch, 3));
          code  <= std_logic_vector(to_unsigned(c, 12));
          valid <= '1';
          wait until rising_edge(clk);
          valid <= '0';
          wait until rising_edge(clk);
        end loop;
      end loop;
    end procedure;

    procedure check(name : string; got : integer; lo : integer; hi : integer) is
    begin
      if got < lo or got > hi then
        errors := errors + 1;
        report "FAIL " & name & ": got " & integer'image(got) &
               ", expected " & integer'image(lo) & ".." & integer'image(hi) severity error;
      else
        report "ok   " & name & " = " & integer'image(got) severity note;
      end if;
    end procedure;
  begin
    for i in 1 to 5 loop wait until rising_edge(clk); end loop;

    -- 1) исходные положения
    send(64);                       -- по 64 отсчёта в канале = 4 обновления
    for i in 1 to 5 loop wait until rising_edge(clk); end loop;
    check("delay (pot=0)",    to_integer(unsigned(o_delay)), 73, 73);
    check("mix (pot=max)",    to_integer(unsigned(o_mix)),   256, 256);
    check("lp (pot=mid)",     to_integer(unsigned(o_lp)),    64, 64);
    check("hp (pot=max)",     to_integer(unsigned(o_hp)),    256, 256);
    check("fb (no pot)",      to_integer(unsigned(o_fb)),    0, 0);

    -- 2) задержка на середину хода
    base(0) := 2048;
    send(64);
    for i in 1 to 5 loop wait until rising_edge(clk); end loop;
    check("delay (pot=mid)",  to_integer(unsigned(o_delay)), 16040, 16080);

    -- 3) дрожание в пределах гистерезиса не меняет выход
    base(2) := 2050;
    send(64);
    for i in 1 to 5 loop wait until rising_edge(clk); end loop;
    check("lp (hysteresis)",  to_integer(unsigned(o_lp)),    64, 64);

    if errors = 0 then
      report "TEST PASSED: pot_ctrl OK" severity note;
    else
      report "TEST FAILED: " & integer'image(errors) & " errors" severity error;
    end if;
    finished <= '1';
    wait;
  end process;

end sim;