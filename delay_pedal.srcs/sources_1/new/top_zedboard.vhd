----------------------------------------------------------------------------------
-- top_zedboard.vhd - верхний модуль для прототипа на ZedBoard (замена delay_pedal_top)
-- Порты и имена те же, что у прежнего верхнего модуля, поэтому zed_audio.xdc менять не нужно.
-- Параметры задаются кнопками (ctrl_buttons), реле нет.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity top_zedboard is
  Port ( clk_100  : in    STD_LOGIC;   -- 100 МГц, тактовый вход платы
         AC_ADR0  : out   STD_LOGIC;
         AC_ADR1  : out   STD_LOGIC;
         AC_GPIO0 : out   STD_LOGIC;
         AC_GPIO1 : in    STD_LOGIC;
         AC_GPIO2 : in    STD_LOGIC;
         AC_GPIO3 : in    STD_LOGIC;
         AC_MCLK  : out   STD_LOGIC;
         AC_SCK   : out   STD_LOGIC;
         AC_SDA   : inout STD_LOGIC;
         BTNC     : in    STD_LOGIC;
         BTNU     : in    STD_LOGIC;
         BTND     : in    STD_LOGIC;
         BTNR     : in    STD_LOGIC;
         BTNL     : in    STD_LOGIC
         );
end top_zedboard;

architecture Behavioral of top_zedboard is

  signal clk       : std_logic;
  signal p_delay   : std_logic_vector(15 downto 0);
  signal p_mix, p_lp, p_hp, p_fb : std_logic_vector(8 downto 0);
  signal toggle    : std_logic;
  signal force_rst : std_logic;

begin

  -- ctrl_buttons работает на внутреннем такте ядра (o_clk_100 после MMCM), как и вся логика

  i_ctrl : entity work.ctrl_buttons
    port map (
      i_clk => clk,
      i_btnc => BTNC, i_btnu => BTNU, i_btnd => BTND, i_btnl => BTNL, i_btnr => BTNR,
      o_delay => p_delay, o_mix => p_mix, o_lp => p_lp, o_hp => p_hp, o_fb => p_fb,
      o_toggle => toggle, o_force_rst => force_rst);

  i_core : entity work.delay_pedal_core
    generic map (HAS_RELAY => false, START_ON => true)
    port map (
      clk_100  => clk_100,
      AC_MCLK  => AC_MCLK, AC_ADR0 => AC_ADR0, AC_ADR1 => AC_ADR1, AC_SCK => AC_SCK,
      AC_SDA   => AC_SDA,  AC_GPIO0 => AC_GPIO0, AC_GPIO1 => AC_GPIO1,
      AC_GPIO2 => AC_GPIO2, AC_GPIO3 => AC_GPIO3,
      i_delay => p_delay, i_mix => p_mix, i_lp => p_lp, i_hp => p_hp, i_fb => p_fb,
      i_toggle => toggle, i_force_rst => force_rst,
      o_relay => open, o_led => open, o_ready => open, o_clk => clk);

end Behavioral;