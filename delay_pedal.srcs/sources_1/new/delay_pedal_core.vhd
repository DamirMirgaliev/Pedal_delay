----------------------------------------------------------------------------------
-- delay_pedal_core.vhd - ядро педали: не привязано к плате и физическим выводам
--
-- Ядро содержит всё, что одинаково на ZedBoard и на плате педали: кодек (audio_top),
-- сброс по включению и реле (fx_ctrl), сглаживание параметров (slew) и два канала
-- эффекта (delay_channel). Источник параметров (кнопки или потенциометры) и сами
-- выводы кристалла подключаются в верхних модулях top_zedboard / top_pedal.
--
-- Параметры (приходят от источника управления, все уровни 0..256, где 256 = 1,0):
--   i_delay  полная задержка эха, отсчётов (73..32065; при 48 кГц 1,5 мс .. 668 мс)
--   i_mix    баланс: 0 = только исходный сигнал, 256 = только эхо
--            (dry = 256 - mix, wet = mix; например mix = 192: эхо преобладает)
--   i_lp     уровень НЧ-составляющей эха (тембр повторов)
--   i_hp     уровень ВЧ-составляющей эха
--   i_fb     обратная связь (повторы); ограничена до 240 (0,94), чтобы повторы затухали
-- Все параметры сглаживаются (щелчки и "зиппер-шум" убраны).
--
-- Выключенный эффект: микс уходит в 0 -> проходит только исходный сигнал.
-- На плате с реле (HAS_RELAY) эффект выключается обходом: сначала ЦАП плавно
-- заглушается, затем отпускается реле (подробнее в fx_ctrl.vhd).
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity delay_pedal_core is
  generic (
    HAS_RELAY : boolean := false;     -- true: плата педали с реле обхода
    START_ON  : boolean := true       -- включить эффект после сброса
  );
  port (
    clk_100     : in    std_logic;    -- 100 МГц, тактовый вход платы
    -- кодек ADAU1761
    AC_MCLK     : out   std_logic;
    AC_ADR0     : out   std_logic;    -- на плате педали не выводятся (адрес задаётся подтяжкой)
    AC_ADR1     : out   std_logic;
    AC_SCK      : out   std_logic;
    AC_SDA      : inout std_logic;
    AC_GPIO0    : out   std_logic;
    AC_GPIO1    : in    std_logic;
    AC_GPIO2    : in    std_logic;
    AC_GPIO3    : in    std_logic;
    -- параметры эффекта
    i_delay     : in    std_logic_vector(15 downto 0);
    i_mix       : in    std_logic_vector(8 downto 0);
    i_lp        : in    std_logic_vector(8 downto 0);
    i_hp        : in    std_logic_vector(8 downto 0);
    i_fb        : in    std_logic_vector(8 downto 0);
    -- управление
    i_toggle    : in    std_logic;    -- импульс: включить/выключить эффект
    i_force_rst : in    std_logic;    -- принудительный сброс
    o_relay     : out   std_logic;
    o_led       : out   std_logic;
    o_ready     : out   std_logic;
    o_clk       : out   std_logic     -- внутренний такт 100 МГц: на нём должен работать источник параметров
  );
end delay_pedal_core;

architecture Behavioral of delay_pedal_core is

  constant FB_MAX : natural := 240;

  signal clk        : std_logic;                       -- 100 МГц (o_clk_100 из audio_top)
  signal new_sample : std_logic;
  signal locked     : std_logic;
  signal line_in_l  : std_logic_vector(23 downto 0);
  signal line_in_r  : std_logic_vector(23 downto 0);
  signal hphone_l   : std_logic_vector(23 downto 0);
  signal hphone_r   : std_logic_vector(23 downto 0);
  signal val_l      : std_logic;
  signal val_r      : std_logic;

  signal rst        : std_logic;
  signal flush      : std_logic;
  signal fx_on      : std_logic;
  signal master     : std_logic_vector(8 downto 0);

  signal mix_tgt    : std_logic_vector(8 downto 0);
  signal fb_tgt     : std_logic_vector(8 downto 0);
  signal delay_s    : std_logic_vector(15 downto 0);
  signal mix_s      : std_logic_vector(8 downto 0);
  signal lp_s       : std_logic_vector(8 downto 0);
  signal hp_s       : std_logic_vector(8 downto 0);
  signal fb_s       : std_logic_vector(8 downto 0);
  signal gain_dry   : std_logic_vector(8 downto 0) := (others => '0');
  signal gain_wet   : std_logic_vector(8 downto 0) := (others => '0');

begin

  o_clk <= clk;

  -- ================= кодек =================
  i_audio : entity work.audio_top
    port map (
      clk_100              => clk_100,
      AC_MCLK              => AC_MCLK,
      AC_ADR0              => AC_ADR0,
      AC_ADR1              => AC_ADR1,
      AC_SCK               => AC_SCK,
      AC_SDA               => AC_SDA,
      AC_GPIO0             => AC_GPIO0,
      AC_GPIO1             => AC_GPIO1,
      AC_GPIO2             => AC_GPIO2,
      AC_GPIO3             => AC_GPIO3,
      hphone_l             => hphone_l,
      hphone_l_valid       => val_l,
      hphone_r             => hphone_r,
      hphone_r_valid_dummy => val_l,       -- общий valid для обоих каналов
      line_in_l            => line_in_l,
      line_in_r            => line_in_r,
      o_clk_100            => clk,
      new_sample           => new_sample,
      sample_clk_48k       => open,        -- не используется (это уровень, а не такт)
      o_locked             => locked
    );

  -- ================= сброс, эффект, реле =================
  i_fx : entity work.fx_ctrl
    generic map (HAS_RELAY => HAS_RELAY, START_ON => START_ON)
    port map (
      i_clk       => clk,
      i_locked    => locked,
      i_tick      => new_sample,
      i_force_rst => i_force_rst,
      i_toggle    => i_toggle,
      o_rst       => rst,
      o_ready     => o_ready,
      o_fx_on     => fx_on,
      o_relay     => o_relay,
      o_led       => o_led,
      o_master    => master,
      o_flush     => flush
    );

  -- ================= сглаживание параметров =================
  -- при выключенном эффекте микс плавно уходит в 0 (проходит только исходный сигнал)
  mix_tgt <= i_mix when fx_on = '1' else (others => '0');
  fb_tgt  <= i_fb  when unsigned(i_fb) <= FB_MAX else std_logic_vector(to_unsigned(FB_MAX, 9));

  i_slew_delay : entity work.slew
    generic map (WIDTH => 16, STEP => 1, DIV => 8)
    port map (i_clk => clk, i_rst => rst, i_tick => new_sample, i_target => i_delay, o_value => delay_s);

  i_slew_mix : entity work.slew
    generic map (WIDTH => 9, STEP => 1, DIV => 1)
    port map (i_clk => clk, i_rst => rst, i_tick => new_sample, i_target => mix_tgt, o_value => mix_s);

  i_slew_lp : entity work.slew
    generic map (WIDTH => 9, STEP => 1, DIV => 1)
    port map (i_clk => clk, i_rst => rst, i_tick => new_sample, i_target => i_lp, o_value => lp_s);

  i_slew_hp : entity work.slew
    generic map (WIDTH => 9, STEP => 1, DIV => 1)
    port map (i_clk => clk, i_rst => rst, i_tick => new_sample, i_target => i_hp, o_value => hp_s);

  i_slew_fb : entity work.slew
    generic map (WIDTH => 9, STEP => 1, DIV => 1)
    port map (i_clk => clk, i_rst => rst, i_tick => new_sample, i_target => fb_tgt, o_value => fb_s);

  -- микс и общий уровень: dry = (256 - mix) * master / 256,  wet = mix * master / 256
  gain_proc : process(clk)
    variable m : unsigned(8 downto 0);
    variable p : unsigned(17 downto 0);
  begin
    if rising_edge(clk) then
      m := unsigned(mix_s);
      if m > 256 then
        m := to_unsigned(256, 9);
      end if;
      p := (to_unsigned(256, 9) - m) * unsigned(master);
      gain_dry <= std_logic_vector(resize(shift_right(p, 8), 9));
      p := m * unsigned(master);
      gain_wet <= std_logic_vector(resize(shift_right(p, 8), 9));
    end if;
  end process;

  -- ================= два канала эффекта =================
  chan_l : entity work.delay_channel
    port map (
      i_clk => clk, i_rst => rst, i_flush => flush, i_val => new_sample, i_dat => line_in_l,
      i_delay => delay_s,
      i_gain_dry => gain_dry, i_gain_wet => gain_wet,
      i_gain_lp => lp_s, i_gain_hp => hp_s, i_gain_fb => fb_s,
      o_val => val_l, o_dat => hphone_l);

  chan_r : entity work.delay_channel
    port map (
      i_clk => clk, i_rst => rst, i_flush => flush, i_val => new_sample, i_dat => line_in_r,
      i_delay => delay_s,
      i_gain_dry => gain_dry, i_gain_wet => gain_wet,
      i_gain_lp => lp_s, i_gain_hp => hp_s, i_gain_fb => fb_s,
      o_val => val_r, o_dat => hphone_r);

end Behavioral;