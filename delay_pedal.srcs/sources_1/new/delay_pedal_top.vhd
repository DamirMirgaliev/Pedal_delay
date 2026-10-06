----------------------------------------------------------------------------------
-- delay_pedal_top.vhd - верхний модуль проекта (замена action.vhd)
--
-- Порты те же, что у старого action.vhd, поэтому текущий .xdc менять не нужно.
--
-- Структура:
--   audio_top (кодек ADAU1761, I2S, такт o_clk_100, строб new_sample)
--     line_in_l/r --> delay_channel (L) / delay_channel (R) --> hphone_l/r
--   Блок параметров (сейчас от кнопок; позже его заменит модуль потенциометров -
--   достаточно подать те же три сигнала: delay_val, gain_lp, gain_hp):
--     BTNC - сброс (пока нажата)
--     BTNU - эффект вкл/выкл
--     BTNL - уровень НЧ-составляющей эха (0, 0.25, 0.5, 0.75, 1.0 по кругу)
--     BTNR - уровень ВЧ-составляющей эха (так же)
--     BTND - время задержки (100, 250, 500, 667 мс по кругу)
--   Кнопки: короткое нажатие = удержание не менее 0,1 с (это и есть антидребезг).
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity delay_pedal_top is
  Port ( clk_100  : in    STD_LOGIC;   -- 100 МГц, тактовый вход платы
         AC_ADR0  : out   STD_LOGIC;   -- управление кодеком ADAU1761
         AC_ADR1  : out   STD_LOGIC;
         AC_GPIO0 : out   STD_LOGIC;   -- I2S MISO
         AC_GPIO1 : in    STD_LOGIC;   -- I2S MOSI
         AC_GPIO2 : in    STD_LOGIC;   -- I2S bclk
         AC_GPIO3 : in    STD_LOGIC;   -- I2S LR
         AC_MCLK  : out   STD_LOGIC;
         AC_SCK   : out   STD_LOGIC;
         AC_SDA   : inout STD_LOGIC;
         BTNC     : in    STD_LOGIC;
         BTNU     : in    STD_LOGIC;
         BTND     : in    STD_LOGIC;
         BTNR     : in    STD_LOGIC;
         BTNL     : in    STD_LOGIC
         );
end delay_pedal_top;

architecture Behavioral of delay_pedal_top is

  -- ---------- аудиотракт ----------
  signal clk          : std_logic;                       -- 100 МГц (o_clk_100 из audio_top)
  signal new_sample   : std_logic;
  signal line_in_l    : std_logic_vector(23 downto 0);
  signal line_in_r    : std_logic_vector(23 downto 0);
  signal hphone_l     : std_logic_vector(23 downto 0) := (others => '0');
  signal hphone_r     : std_logic_vector(23 downto 0) := (others => '0');
  signal val_l, val_r : std_logic;

  -- ---------- кнопки ----------
  signal btn_s0, btn_s1 : std_logic_vector(4 downto 0) := (others => '0');  -- синхронизатор 2 триггера
  signal rst            : std_logic;
  signal up_short, down_short, left_short, right_short : std_logic;

  -- ---------- параметры эффекта ----------
  type gain_tab_t  is array (0 to 4) of natural;
  type delay_tab_t is array (0 to 3) of natural;
  constant GAIN_TAB  : gain_tab_t  := (0, 64, 128, 192, 256);      -- 256 = 1,0
  constant DELAY_TAB : delay_tab_t := (4800, 12000, 24000, 32000); -- отсчётов: 100, 250, 500, 667 мс

  signal effect_on : std_logic := '1';
  signal lvl_lp    : natural range 0 to 4 := 2;
  signal lvl_hp    : natural range 0 to 4 := 2;
  signal dly_idx   : natural range 0 to 3 := 2;

  signal delay_val : std_logic_vector(15 downto 0);
  signal gain_dry  : std_logic_vector(8 downto 0);
  signal gain_lp   : std_logic_vector(8 downto 0);
  signal gain_hp   : std_logic_vector(8 downto 0);

begin

  -- ================= аудио =================
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
      sample_clk_48k       => open         -- не используется (это уровень, а не такт)
    );

  gain_dry <= std_logic_vector(to_unsigned(256, 9));   -- исходный сигнал: 1,0 (в будущем ручка Mix)

  chan_l : entity work.delay_channel
    port map (
      i_clk => clk, i_rst => rst, i_val => new_sample, i_dat => line_in_l,
      i_enable => effect_on, i_delay => delay_val,
      i_gain_dry => gain_dry, i_gain_lp => gain_lp, i_gain_hp => gain_hp,
      o_val => val_l, o_dat => hphone_l);

  chan_r : entity work.delay_channel
    port map (
      i_clk => clk, i_rst => rst, i_val => new_sample, i_dat => line_in_r,
      i_enable => effect_on, i_delay => delay_val,
      i_gain_dry => gain_dry, i_gain_lp => gain_lp, i_gain_hp => gain_hp,
      o_val => val_r, o_dat => hphone_r);

  -- ================= кнопки =================
  -- кнопки асинхронны к такту: сначала два триггера синхронизации
  sync_proc : process(clk)
  begin
    if rising_edge(clk) then
      btn_s0 <= BTNR & BTNL & BTND & BTNU & BTNC;
      btn_s1 <= btn_s0;
    end if;
  end process;

  rst <= btn_s1(0);   -- BTNC: сброс, пока нажата

  btn_u : entity work.button
    generic map (FCLK => 100.0e6, SHORT_PRESS_DURATION => 0.1, LONG_PRESS_DURATION => 1.0)
    port map (i_clk => clk, i_press => btn_s1(1), o_short => up_short,    o_long => open);
  btn_d : entity work.button
    generic map (FCLK => 100.0e6, SHORT_PRESS_DURATION => 0.1, LONG_PRESS_DURATION => 1.0)
    port map (i_clk => clk, i_press => btn_s1(2), o_short => down_short,  o_long => open);
  btn_l : entity work.button
    generic map (FCLK => 100.0e6, SHORT_PRESS_DURATION => 0.1, LONG_PRESS_DURATION => 1.0)
    port map (i_clk => clk, i_press => btn_s1(3), o_short => left_short,  o_long => open);
  btn_r : entity work.button
    generic map (FCLK => 100.0e6, SHORT_PRESS_DURATION => 0.1, LONG_PRESS_DURATION => 1.0)
    port map (i_clk => clk, i_press => btn_s1(4), o_short => right_short, o_long => open);

  -- ================= параметры эффекта (временно от кнопок) =================
  param_proc : process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        effect_on <= '1';
        lvl_lp    <= 2;
        lvl_hp    <= 2;
        dly_idx   <= 2;
      else
        if up_short = '1' then
          effect_on <= not effect_on;
        end if;
        if left_short = '1' then
          if lvl_lp = 4 then lvl_lp <= 0; else lvl_lp <= lvl_lp + 1; end if;
        end if;
        if right_short = '1' then
          if lvl_hp = 4 then lvl_hp <= 0; else lvl_hp <= lvl_hp + 1; end if;
        end if;
        if down_short = '1' then
          if dly_idx = 3 then dly_idx <= 0; else dly_idx <= dly_idx + 1; end if;
        end if;
      end if;
    end if;
  end process;

  gain_lp   <= std_logic_vector(to_unsigned(GAIN_TAB(lvl_lp), 9));
  gain_hp   <= std_logic_vector(to_unsigned(GAIN_TAB(lvl_hp), 9));
  delay_val <= std_logic_vector(to_unsigned(DELAY_TAB(dly_idx), 16));

end Behavioral;