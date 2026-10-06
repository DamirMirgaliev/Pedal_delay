----------------------------------------------------------------------------------
-- tb_delay_line.vhd - самопровер€ющийс€ тестбенч дл€ delay_line
-- ѕодаЄт отсчЄты k*1000 (k = 1, 2, 3 ...) и провер€ет, что на выходе:
--   первые D отсчЄтов = 0, далее (k - D)*1000, т.е. вход, задержанный на D отсчЄтов.
-- ѕериод отсчЄтов в симул€ции сокращЄн до 100 тактов (в железе ~2083 такта при 48 к√ц).
-- ƒобавить как Simulation Source. ƒл€ симул€ции нужен сгенерированный IP fifo_delay_axis.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_delay_line is
end tb_delay_line;

architecture sim of tb_delay_line is
  constant D            : natural := 16;     -- провер€ема€ задержка, отсчЄтов
  constant N_SAMPLES    : natural := 200;
  constant CLK_PER_SMPL : natural := 100;

  signal clk   : std_logic := '0';
  signal rst   : std_logic := '1';
  signal val   : std_logic := '0';
  signal dat   : std_logic_vector(23 downto 0) := (others => '0');
  signal delay : std_logic_vector(15 downto 0) := std_logic_vector(to_unsigned(D, 16));
  signal o_val : std_logic;
  signal o_dat : std_logic_vector(23 downto 0);

  signal n_out  : natural := 0;
  signal errors : natural := 0;
begin

  clk <= not clk after 5 ns;   -- 100 ћ√ц

  dut : entity work.delay_line
    generic map (DAT_WIDTH => 24, MAX_DELAY => 32000, MIN_DELAY => 8)
    port map (i_clk => clk, i_rst => rst, i_val => val, i_dat => dat,
              i_delay => delay, o_val => o_val, o_dat => o_dat);

  stim : process
  begin
    rst <= '1';
    for i in 1 to 20 loop wait until rising_edge(clk); end loop;
    rst <= '0';
    for i in 1 to 20 loop wait until rising_edge(clk); end loop;

    for k in 1 to N_SAMPLES loop
      wait until rising_edge(clk);
      dat <= std_logic_vector(to_signed(k * 1000, 24));
      val <= '1';
      wait until rising_edge(clk);
      val <= '0';
      for j in 1 to CLK_PER_SMPL loop wait until rising_edge(clk); end loop;
    end loop;

    for j in 1 to 50 loop wait until rising_edge(clk); end loop;
    if errors = 0 then
      report "TEST PASSED: " & integer'image(n_out) & " outputs checked" severity note;
    else
      report "TEST FAILED: " & integer'image(errors) & " errors" severity error;
    end if;
    wait;   -- конец стимулов (симул€цию можно остановить или оставить до конца run)
  end process;

  check : process(clk)
    variable e   : natural;
    variable exp : integer;
  begin
    if rising_edge(clk) then
      if o_val = '1' then
        e := n_out + 1;
        n_out <= e;
        if e <= D then
          exp := 0;
        else
          exp := (e - D) * 1000;
        end if;
        if signed(o_dat) /= to_signed(exp, 24) then
          errors <= errors + 1;
          report "Mismatch at output " & integer'image(e) &
                 ": got " & integer'image(to_integer(signed(o_dat))) &
                 ", expected " & integer'image(exp) severity error;
        end if;
      end if;
    end if;
  end process;

end sim;