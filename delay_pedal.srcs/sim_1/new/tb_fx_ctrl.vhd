----------------------------------------------------------------------------------
-- tb_fx_ctrl.vhd - проверка fx_ctrl: сброс по включению, переключение эффекта, реле, заглушение
-- ¬ремена сокращены через generic (CLK_HZ = 10 к√ц -> 10 тактов на "мс", RELAY_MS = 3,
-- READY_SAMPLES = 8, отсчЄты каждые 100 тактов).
-- DUT1: плата с реле (HAS_RELAY = true, START_ON = false).
-- DUT2: ZedBoard (HAS_RELAY = false, START_ON = true).
-- ѕосто€нно провер€етс€, что реле не коммутируетс€ под звуком:
--   master > 0 допустимо только при включЄнном реле.
-- „иста€ логика, симул€ци€ быстра€.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_fx_ctrl is
end tb_fx_ctrl;

architecture sim of tb_fx_ctrl is
  constant TICK_CLKS : natural := 100;

  signal clk      : std_logic := '0';
  signal finished : std_logic := '0';
  signal locked   : std_logic := '0';
  signal tick     : std_logic := '0';
  signal tick_en  : std_logic := '0';
  signal force_rst: std_logic := '0';
  signal toggle   : std_logic := '0';

  -- DUT1
  signal rst1, ready1, fx1, relay1, led1, flush1 : std_logic;
  signal master1  : std_logic_vector(8 downto 0);
  -- DUT2
  signal rst2, ready2, fx2, relay2, led2, flush2 : std_logic;
  signal master2  : std_logic_vector(8 downto 0);

  signal saw_flush1 : std_logic := '0';
  signal errors     : natural := 0;
begin

  clk_gen : process
  begin
    while finished = '0' loop
      clk <= '0'; wait for 5 ns;
      clk <= '1'; wait for 5 ns;
    end loop;
    wait;
  end process;

  -- строб new_sample каждые TICK_CLKS тактов (когда разрешЄн)
  tick_gen : process
  begin
    wait until rising_edge(clk);
    while finished = '0' loop
      if tick_en = '1' then
        tick <= '1';
        wait until rising_edge(clk);
        tick <= '0';
        for i in 2 to TICK_CLKS loop wait until rising_edge(clk); end loop;
      else
        wait until rising_edge(clk);
      end if;
    end loop;
    wait;
  end process;

  dut1 : entity work.fx_ctrl
    generic map (HAS_RELAY => true, START_ON => false, CLK_HZ => 10_000, RELAY_MS => 3,
                 READY_SAMPLES => 8, GAP_MIN => 90, GAP_MAX => 110, GAP_LIMIT => 400)
    port map (i_clk => clk, i_locked => locked, i_tick => tick, i_force_rst => force_rst,
              i_toggle => toggle, o_rst => rst1, o_ready => ready1, o_fx_on => fx1,
              o_relay => relay1, o_led => led1, o_master => master1, o_flush => flush1);

  dut2 : entity work.fx_ctrl
    generic map (HAS_RELAY => false, START_ON => true, CLK_HZ => 10_000, RELAY_MS => 3,
                 READY_SAMPLES => 8, GAP_MIN => 90, GAP_MAX => 110, GAP_LIMIT => 400)
    port map (i_clk => clk, i_locked => locked, i_tick => tick, i_force_rst => force_rst,
              i_toggle => toggle, o_rst => rst2, o_ready => ready2, o_fx_on => fx2,
              o_relay => relay2, o_led => led2, o_master => master2, o_flush => flush2);

  -- инвариант: звук (master > 0) только при включЄнном реле (вне сброса)
  inv : process(clk)
  begin
    if rising_edge(clk) then
      if rst1 = '0' and unsigned(master1) > 0 and relay1 = '0' then
        errors <= errors + 1;
        report "relay released/engaged under sound (master>0 with relay off)" severity error;
      end if;
      if flush1 = '1' then saw_flush1 <= '1'; end if;
    end if;
  end process;

  stim : process
    variable err : natural := 0;

    procedure wait_clks(n : natural) is
    begin
      for i in 1 to n loop wait until rising_edge(clk); end loop;
    end procedure;

    procedure pulse_toggle is
    begin
      wait until rising_edge(clk);
      toggle <= '1';
      wait until rising_edge(clk);
      toggle <= '0';
    end procedure;

    procedure expect(name : string; cond : boolean) is
    begin
      if not cond then
        err := err + 1;
        report "FAIL: " & name severity error;
      else
        report "ok:   " & name severity note;
      end if;
    end procedure;
  begin
    -- 0) до захвата MMCM и без отсчЄтов - сброс активен
    wait_clks(20);
    expect("reset active before lock/samples", rst1 = '1' and relay1 = '0');

    -- 1) MMCM захвачен, пошли отсчЄты -> через 8+ верных отсчЄтов сброс снимаетс€
    locked  <= '1';
    tick_en <= '1';
    wait_clks(TICK_CLKS * 14);
    expect("ready after stable samples", ready1 = '1' and rst1 = '0');
    expect("relay off, effect off (DUT1)", relay1 = '0' and fx1 = '0');
    expect("ZedBoard variant starts effect automatically (DUT2)", fx2 = '1' and relay2 = '0');

    -- 2) включение эффекта на плате с реле
    pulse_toggle;
    wait_clks(5);
    expect("relay engaged at once, sound still muted", relay1 = '1' and fx1 = '1' and unsigned(master1) = 0);
    expect("flush pulse issued on enable", saw_flush1 = '1');
    wait_clks(TICK_CLKS * 300);
    expect("master ramped up to 1.0", unsigned(master1) = 256);
    expect("ZedBoard variant toggled off (DUT2)", fx2 = '0');

    -- 3) выключение: сначала звук затихает, потом отпускаетс€ реле
    pulse_toggle;
    wait_clks(TICK_CLKS * 5);
    expect("relay still on while fading out", relay1 = '1' and unsigned(master1) > 0);
    wait_clks(TICK_CLKS * 300);
    expect("bypass: relay released, master 0, effect off", relay1 = '0' and unsigned(master1) = 0 and fx1 = '0');
    expect("ZedBoard variant toggled on (DUT2)", fx2 = '1');

    -- 4) снова включить, затем принудительный сброс
    pulse_toggle;
    wait_clks(TICK_CLKS * 300);
    expect("enabled again", relay1 = '1' and unsigned(master1) = 256);
    wait until rising_edge(clk);
    force_rst <= '1';
    wait until rising_edge(clk);
    force_rst <= '0';
    wait_clks(10);
    expect("forced reset: reset active, relay released", rst1 = '1' and relay1 = '0');
    wait_clks(TICK_CLKS * 14);
    expect("recovered after forced reset, effect off", rst1 = '0' and fx1 = '0' and relay1 = '0');

    -- 5) пропали отсчЄты (кодек остановилс€) -> сброс
    tick_en <= '0';
    wait_clks(600);
    expect("samples lost -> reset", rst1 = '1');

    if err = 0 and errors = 0 then
      report "TEST PASSED: fx_ctrl OK" severity note;
    else
      report "TEST FAILED: " & integer'image(err) & " checks, " & integer'image(errors) & " invariant violations" severity error;
    end if;
    finished <= '1';
    wait;
  end process;

end sim;