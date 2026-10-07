----------------------------------------------------------------------------------
-- delay_channel.vhd - цепочка эффекта для ОДНОГО канала (в ядре два экземпляра: L и R)
--
--   i_dat --+--------------------------------- * g_dry --------------------+
--           |                                                              |
--           +-(+ fb)-> delay_line -+-> eq_lpf -> * g_lp -+                 +-> сумма -> насыщение -> o_dat
--             ^                    |                     +-> эхо --* g_wet-+
--             |                    +-> eq_hpf -> * g_hp -+    |
--             +------------------------ * g_fb ---------------+
--
--   * Фильтры обрабатывают только задержанный сигнал, исходный (dry) их не проходит.
--   * Эхо = g_lp*LPF + g_hp*HPF (тембр повторов). Выход = g_dry*dry + g_wet*эхо.
--     Микс (баланс сухой/эхо) и общий уровень вычисляются в ядре: g_dry, g_wet.
--   * Обратная связь: эхо * g_fb добавляется к входу линии задержки, получаются повторы.
--     g_fb должен быть < 256 (< 1,0), иначе повторы нарастают; в ядре ограничено 240.
--   * Все коэффициенты усиления 9 бит без знака: 0..256, где 256 = 1,0. Больше 256 -> 256.
--
-- Время задержки: i_delay = ПОЛНАЯ задержка эха в отсчётах (от входа до центра эха).
--   Линия задержки получает i_delay - FILTER_COMP: компенсация групповой задержки
--   FIR (64 отсчёта) и одного отсчёта обратной связи, поэтому расстояние между повторами
--   равно i_delay. Диапазон: FILTER_COMP + 8 .. FILTER_COMP + 32000 (73..32065).
--
-- Тайминг: o_val приходит примерно через 1,6 мкс после i_val (FIR 137 тактов + конвейер),
-- в пределах того же периода отсчётов (2083 такта). i_dat и коэффициенты должны быть
-- неизменны на это время (audio_top держит line_in весь период, усиления меняются
-- только по new_sample).
--
-- DSP: перед каждым умножителем стоят входные регистры, после него два регистра
-- (MREG и PREG) - так Vivado использует конвейер DSP48E1 (нет замечаний DPIP/DPOP).
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity delay_channel is
  generic (
    FILTER_COMP : natural := 65        -- 64 (FIR) + 1 (отсчёт обратной связи)
  );
  port (
    i_clk      : in  std_logic;                       -- 100 МГц (o_clk_100)
    i_rst      : in  std_logic;                       -- активный уровень '1'
    i_flush    : in  std_logic;                       -- импульс: очистить линию задержки и обратную связь
    i_val      : in  std_logic;                       -- new_sample
    i_dat      : in  std_logic_vector(23 downto 0);   -- отсчёт с входа (line in)
    i_delay    : in  std_logic_vector(15 downto 0);   -- полная задержка эха, отсчётов
    i_gain_dry : in  std_logic_vector(8 downto 0);    -- уровень исходного сигнала 0..256
    i_gain_wet : in  std_logic_vector(8 downto 0);    -- уровень эха на выходе 0..256
    i_gain_lp  : in  std_logic_vector(8 downto 0);    -- НЧ-составляющая эха 0..256
    i_gain_hp  : in  std_logic_vector(8 downto 0);    -- ВЧ-составляющая эха 0..256
    i_gain_fb  : in  std_logic_vector(8 downto 0);    -- обратная связь 0..256 (<256!)
    o_val      : out std_logic := '0';                -- 1 такт: готов выходной отсчёт
    o_dat      : out std_logic_vector(23 downto 0) := (others => '0')
  );
end delay_channel;

architecture Behavioral of delay_channel is

  -- вход линии задержки
  signal fb_reg      : signed(23 downto 0) := (others => '0');   -- обратная связь для следующей записи
  signal wr_val      : std_logic := '0';
  signal wr_dat      : std_logic_vector(23 downto 0) := (others => '0');
  signal delay_fifo  : std_logic_vector(15 downto 0);

  -- выходы линии задержки и фильтров
  signal dl_val : std_logic;
  signal dl_dat : std_logic_vector(23 downto 0);
  signal lp_val : std_logic;
  signal lp_dat : std_logic_vector(23 downto 0);
  signal hp_val : std_logic;
  signal hp_dat : std_logic_vector(23 downto 0);

  -- признак готовности данных по ступеням конвейера
  signal v : std_logic_vector(0 to 7) := (others => '0');

  -- ступень 0: входные регистры первых умножителей
  signal a_lp, a_hp : signed(23 downto 0) := (others => '0');
  signal g_lp, g_hp : signed(9 downto 0)  := (others => '0');
  -- ступени 1-2: произведения (MREG, PREG)
  signal m_lp, m_hp : signed(33 downto 0) := (others => '0');
  signal p_lp, p_hp : signed(33 downto 0) := (others => '0');
  -- ступень 3: эхо
  signal echo       : signed(23 downto 0) := (others => '0');
  -- ступень 4: входные регистры вторых умножителей
  signal a_d        : signed(23 downto 0) := (others => '0');
  signal g_d, g_w, g_f : signed(9 downto 0) := (others => '0');
  -- ступени 5-6: произведения
  signal m_d, m_w, m_f : signed(33 downto 0) := (others => '0');
  signal p_d, p_w, p_f : signed(33 downto 0) := (others => '0');
  -- ступень 7: сумма и обратная связь
  signal sum_out    : signed(25 downto 0) := (others => '0');
  signal fb_next    : signed(23 downto 0) := (others => '0');

  -- коэффициент 0..256 -> знаковое 10-битное число (с ограничением сверху)
  function gain_of(g : std_logic_vector(8 downto 0)) return signed is
    variable u : unsigned(8 downto 0);
  begin
    u := unsigned(g);
    if u > 256 then
      u := to_unsigned(256, 9);
    end if;
    return signed('0' & std_logic_vector(u));
  end function;

  -- насыщение до 24 бит со знаком (вход не короче 24 бит)
  function sat24(x : signed) return signed is
    constant MAXV : signed(x'length-1 downto 0) := to_signed(8388607, x'length);
    constant MINV : signed(x'length-1 downto 0) := to_signed(-8388608, x'length);
  begin
    if x > MAXV then
      return to_signed(8388607, 24);
    elsif x < MINV then
      return to_signed(-8388608, 24);
    else
      return resize(x, 24);
    end if;
  end function;

begin

  -- задержка линии = полная задержка минус компенсация (не меньше 8)
  delay_fifo <= std_logic_vector(to_unsigned(8, 16))
                  when unsigned(i_delay) < (FILTER_COMP + 8) else
                std_logic_vector(unsigned(i_delay) - FILTER_COMP);

  -- вход линии задержки: отсчёт + обратная связь (с насыщением), строб синхронно с данными
  wr_proc : process(i_clk)
  begin
    if rising_edge(i_clk) then
      wr_val <= i_val;
      wr_dat <= std_logic_vector(sat24(resize(signed(i_dat), 25) + resize(fb_reg, 25)));
    end if;
  end process;

  i_delay_line : entity work.delay_line
    port map (
      i_clk   => i_clk,
      i_rst   => i_rst,
      i_flush => i_flush,
      i_val   => wr_val,
      i_dat   => wr_dat,
      i_delay => delay_fifo,
      o_val   => dl_val,
      o_dat   => dl_dat
    );

  i_lpf : entity work.eq_lpf
    port map (i_clk => i_clk, i_val => dl_val, i_dat => dl_dat, o_val => lp_val, o_dat => lp_dat);

  i_hpf : entity work.eq_hpf
    port map (i_clk => i_clk, i_val => dl_val, i_dat => dl_dat, o_val => hp_val, o_dat => hp_dat);

  -- Конвейер обработки эха. LPF и HPF имеют одинаковую задержку, их o_val совпадают.
  mix_proc : process(i_clk)
    variable e25 : signed(24 downto 0);
  begin
    if rising_edge(i_clk) then
      -- ступень 0
      a_lp <= signed(lp_dat);
      a_hp <= signed(hp_dat);
      g_lp <= gain_of(i_gain_lp);
      g_hp <= gain_of(i_gain_hp);
      v(0) <= lp_val;
      -- ступени 1, 2
      m_lp <= a_lp * g_lp;
      m_hp <= a_hp * g_hp;
      p_lp <= m_lp;
      p_hp <= m_hp;
      v(1) <= v(0);
      v(2) <= v(1);
      -- ступень 3: эхо = LP*g_lp + HP*g_hp
      e25  := resize(shift_right(p_lp, 8), 25) + resize(shift_right(p_hp, 8), 25);
      echo <= sat24(e25);
      v(3) <= v(2);
      -- ступень 4
      a_d  <= signed(i_dat);
      g_d  <= gain_of(i_gain_dry);
      g_w  <= gain_of(i_gain_wet);
      g_f  <= gain_of(i_gain_fb);
      v(4) <= v(3);
      -- ступени 5, 6
      m_d  <= a_d * g_d;
      m_w  <= echo * g_w;
      m_f  <= echo * g_f;
      p_d  <= m_d;
      p_w  <= m_w;
      p_f  <= m_f;
      v(5) <= v(4);
      v(6) <= v(5);
      -- ступень 7: сумма выхода и новое значение обратной связи
      sum_out <= resize(shift_right(p_d, 8), 26) + resize(shift_right(p_w, 8), 26);
      fb_next <= sat24(resize(shift_right(p_f, 8), 25));
      v(7) <= v(6);
      -- ступень 8: выход
      o_val <= v(7);
      if v(7) = '1' then
        o_dat  <= std_logic_vector(sat24(sum_out));
        fb_reg <= fb_next;
      end if;
      -- сброс и очистка
      if i_rst = '1' or i_flush = '1' then
        fb_reg <= (others => '0');
        v      <= (others => '0');
        o_val  <= '0';
      end if;
    end if;
  end process;

end Behavioral;