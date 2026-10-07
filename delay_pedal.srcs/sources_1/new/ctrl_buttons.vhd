----------------------------------------------------------------------------------
-- ctrl_buttons.vhd - источник параметров от кнопок ZedBoard (временна€ замена потенциометров)
--
--  нопки: короткое нажатие = удержание не менее 0,1 с (это и антидребезг, см. button.vhd).
--   без SHIFT:  BTNU - эффект вкл/выкл
--               BTND - врем€ задержки: 100, 250, 500, 667 мс по кругу
--               BTNL - уровень Ќ„-составл€ющей эха: 0, 0,25, 0,5, 0,75, 1,0 по кругу
--               BTNR - уровень ¬„-составл€ющей эха: так же
--   BTNC (удерживаетс€) = SHIFT:
--               BTND - микс (0, 0,25, 0,5, 0,75, 1,0 по кругу)
--               BTNU - обратна€ св€зь (0, 0,25, 0,5, 0,69, 0,88 по кругу)
--   BTNC удержать 3 секунды - принудительный сброс.
-- »нтерфейс параметров такой же, как у модул€ потенциометров pot_ctrl: замен€€ один
-- модуль другим, €дро мен€ть не нужно.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ctrl_buttons is
  generic (
    FCLK : real := 100.0e6
  );
  port (
    i_clk       : in  std_logic;
    i_btnc      : in  std_logic;     -- кнопки асинхронные, синхронизируютс€ внутри
    i_btnu      : in  std_logic;
    i_btnd      : in  std_logic;
    i_btnl      : in  std_logic;
    i_btnr      : in  std_logic;
    o_delay     : out std_logic_vector(15 downto 0);
    o_mix       : out std_logic_vector(8 downto 0);
    o_lp        : out std_logic_vector(8 downto 0);
    o_hp        : out std_logic_vector(8 downto 0);
    o_fb        : out std_logic_vector(8 downto 0);
    o_toggle    : out std_logic;
    o_force_rst : out std_logic
  );
end ctrl_buttons;

architecture Behavioral of ctrl_buttons is

  type gain_tab_t  is array (0 to 4) of natural;
  type delay_tab_t is array (0 to 3) of natural;
  constant GAIN_TAB  : gain_tab_t  := (0, 64, 128, 192, 256);      -- 256 = 1,0
  constant FB_TAB    : gain_tab_t  := (0, 64, 128, 176, 224);
  constant DELAY_TAB : delay_tab_t := (4800, 12000, 24000, 32000); -- отсчЄтов: 100, 250, 500, 667 мс

  signal s0, s1 : std_logic_vector(4 downto 0) := (others => '0');   -- C, U, D, L, R
  signal shift  : std_logic;
  signal u_short, d_short, l_short, r_short, c_long : std_logic;

  signal lvl_lp  : natural range 0 to 4 := 2;
  signal lvl_hp  : natural range 0 to 4 := 2;
  signal lvl_mix : natural range 0 to 4 := 2;
  signal lvl_fb  : natural range 0 to 4 := 0;
  signal dly_idx : natural range 0 to 3 := 2;
  signal toggle_r : std_logic := '0';

begin

  -- синхронизаци€ асинхронных входов (два триггера)
  sync_proc : process(i_clk)
  begin
    if rising_edge(i_clk) then
      s0 <= i_btnr & i_btnl & i_btnd & i_btnu & i_btnc;
      s1 <= s0;
    end if;
  end process;

  shift <= s1(0);

  btn_c : entity work.button
    generic map (FCLK => FCLK, SHORT_PRESS_DURATION => 0.1, LONG_PRESS_DURATION => 3.0)
    port map (i_clk => i_clk, i_press => s1(0), o_short => open, o_long => c_long);
  btn_u : entity work.button
    generic map (FCLK => FCLK, SHORT_PRESS_DURATION => 0.1, LONG_PRESS_DURATION => 1.0)
    port map (i_clk => i_clk, i_press => s1(1), o_short => u_short, o_long => open);
  btn_d : entity work.button
    generic map (FCLK => FCLK, SHORT_PRESS_DURATION => 0.1, LONG_PRESS_DURATION => 1.0)
    port map (i_clk => i_clk, i_press => s1(2), o_short => d_short, o_long => open);
  btn_l : entity work.button
    generic map (FCLK => FCLK, SHORT_PRESS_DURATION => 0.1, LONG_PRESS_DURATION => 1.0)
    port map (i_clk => i_clk, i_press => s1(3), o_short => l_short, o_long => open);
  btn_r : entity work.button
    generic map (FCLK => FCLK, SHORT_PRESS_DURATION => 0.1, LONG_PRESS_DURATION => 1.0)
    port map (i_clk => i_clk, i_press => s1(4), o_short => r_short, o_long => open);

  param_proc : process(i_clk)
  begin
    if rising_edge(i_clk) then
      toggle_r <= '0';

      if u_short = '1' then
        if shift = '1' then
          if lvl_fb = 4 then lvl_fb <= 0; else lvl_fb <= lvl_fb + 1; end if;
        else
          toggle_r <= '1';
        end if;
      end if;

      if d_short = '1' then
        if shift = '1' then
          if lvl_mix = 4 then lvl_mix <= 0; else lvl_mix <= lvl_mix + 1; end if;
        else
          if dly_idx = 3 then dly_idx <= 0; else dly_idx <= dly_idx + 1; end if;
        end if;
      end if;

      if l_short = '1' and shift = '0' then
        if lvl_lp = 4 then lvl_lp <= 0; else lvl_lp <= lvl_lp + 1; end if;
      end if;

      if r_short = '1' and shift = '0' then
        if lvl_hp = 4 then lvl_hp <= 0; else lvl_hp <= lvl_hp + 1; end if;
      end if;
    end if;
  end process;

  o_toggle    <= toggle_r;
  o_force_rst <= c_long;
  o_delay     <= std_logic_vector(to_unsigned(DELAY_TAB(dly_idx), 16));
  o_mix       <= std_logic_vector(to_unsigned(GAIN_TAB(lvl_mix), 9));
  o_lp        <= std_logic_vector(to_unsigned(GAIN_TAB(lvl_lp), 9));
  o_hp        <= std_logic_vector(to_unsigned(GAIN_TAB(lvl_hp), 9));
  o_fb        <= std_logic_vector(to_unsigned(FB_TAB(lvl_fb), 9));

end Behavioral;