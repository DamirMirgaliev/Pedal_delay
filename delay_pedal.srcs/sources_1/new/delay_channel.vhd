----------------------------------------------------------------------------------
-- delay_channel.vhd - цепочка эффекта для ОДНОГО канала (в верхнем модуле два экземпляра: L и R)
--
--   i_dat --+--------------------------------------------- * g_dry ---+
--           |                                                          |
--           +-> delay_line -+-> eq_lpf -> * g_lp -+                    +-> сумма -> насыщение -> o_dat
--                           |                     +--- сумма эха ------+
--                           +-> eq_hpf -> * g_hp -+
--
-- Фильтры обрабатывают ТОЛЬКО задержанный сигнал, исходный (dry) их не проходит.
-- Коэффициенты усиления g_* - 9-битные без знака: 0..256, где 256 = 1,0 (0 дБ).
-- Значения больше 256 ограничиваются до 256. i_enable = '0' выключает эхо (остаётся dry).
--
-- Тайминг: o_val приходит примерно через 1,5 мкс после i_val (задержка FIR 137 тактов
-- + 3 такта конвейера), то есть в пределах того же периода отсчётов (2083 такта).
-- Исходный отсчёт i_dat должен оставаться неизменным до o_val (audio_top держит line_in
-- стабильным весь период 48 кГц).
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity delay_channel is
  port (
    i_clk      : in  std_logic;                       -- 100 МГц (o_clk_100)
    i_rst      : in  std_logic;                       -- активный уровень '1'
    i_val      : in  std_logic;                       -- new_sample
    i_dat      : in  std_logic_vector(23 downto 0);   -- отсчёт с входа (line in)
    i_enable   : in  std_logic;                       -- эффект включён
    i_delay    : in  std_logic_vector(15 downto 0);   -- задержка, отсчётов (8..32000)
    i_gain_dry : in  std_logic_vector(8 downto 0);    -- уровень исходного сигнала 0..256
    i_gain_lp  : in  std_logic_vector(8 downto 0);    -- уровень НЧ-составляющей эха 0..256
    i_gain_hp  : in  std_logic_vector(8 downto 0);    -- уровень ВЧ-составляющей эха 0..256
    o_val      : out std_logic := '0';                -- 1 такт: готов выходной отсчёт
    o_dat      : out std_logic_vector(23 downto 0) := (others => '0')
  );
end delay_channel;

architecture Behavioral of delay_channel is

  signal dl_val : std_logic;
  signal dl_dat : std_logic_vector(23 downto 0);
  signal lp_val : std_logic;
  signal lp_dat : std_logic_vector(23 downto 0);
  signal hp_val : std_logic;
  signal hp_dat : std_logic_vector(23 downto 0);

  signal v1, v2 : std_logic := '0';
  signal p_dry  : signed(33 downto 0) := (others => '0');   -- 24 бита * 10 бит
  signal p_lp   : signed(33 downto 0) := (others => '0');
  signal p_hp   : signed(33 downto 0) := (others => '0');
  signal sum    : signed(25 downto 0) := (others => '0');

  -- коэффициент 0..256 -> знаковое 10-битное число (с ограничением и отключением)
  function gain_of(g : std_logic_vector(8 downto 0); en : std_logic) return signed is
    variable u : unsigned(8 downto 0);
  begin
    u := unsigned(g);
    if u > 256 then
      u := to_unsigned(256, 9);
    end if;
    if en = '0' then
      u := (others => '0');
    end if;
    return signed('0' & std_logic_vector(u));
  end function;

begin

  i_delay_line : entity work.delay_line
    port map (
      i_clk   => i_clk,
      i_rst   => i_rst,
      i_val   => i_val,
      i_dat   => i_dat,
      i_delay => i_delay,
      o_val   => dl_val,
      o_dat   => dl_dat
    );

  i_lpf : entity work.eq_lpf
    port map (
      i_clk => i_clk,
      i_val => dl_val,
      i_dat => dl_dat,
      o_val => lp_val,
      o_dat => lp_dat
    );

  i_hpf : entity work.eq_hpf
    port map (
      i_clk => i_clk,
      i_val => dl_val,
      i_dat => dl_dat,
      o_val => hp_val,
      o_dat => hp_dat
    );

  -- Конвейер из трёх ступеней (времени на отсчёт хватает с огромным запасом):
  --   1) умножение на коэффициенты усиления
  --   2) сложение трёх слагаемых (после деления на 256)
  --   3) насыщение до 24 бит
  -- LPF и HPF имеют одинаковую задержку, их o_val совпадают; ориентируемся на lp_val.
  mix_proc : process(i_clk)
  begin
    if rising_edge(i_clk) then
      -- ступень 1
      p_dry <= signed(i_dat)  * gain_of(i_gain_dry, '1');
      p_lp  <= signed(lp_dat) * gain_of(i_gain_lp,  i_enable);
      p_hp  <= signed(hp_dat) * gain_of(i_gain_hp,  i_enable);
      v1    <= lp_val;

      -- ступень 2
      sum <= resize(shift_right(p_dry, 8), 26) +
             resize(shift_right(p_lp,  8), 26) +
             resize(shift_right(p_hp,  8), 26);
      v2  <= v1;

      -- ступень 3
      o_val <= v2;
      if v2 = '1' then
        if sum > 8388607 then
          o_dat <= x"7FFFFF";
        elsif sum < -8388608 then
          o_dat <= x"800000";
        else
          o_dat <= std_logic_vector(sum(23 downto 0));
        end if;
      end if;
    end if;
  end process;

end Behavioral;