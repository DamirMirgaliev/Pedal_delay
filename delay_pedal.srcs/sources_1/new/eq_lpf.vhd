----------------------------------------------------------------------------------
-- eq_lpf.vhd  -  НЧ-фильтр (LPF) одного канала (L или R): обёртка над IP fir_lpf_129t_b16
-- Для стерео в верхнем модуле подключаются ДВА экземпляра (левый и правый канал).
--
-- IP: FIR Compiler 7.2, 129 коэффициентов, 16 бит (целые), вход 24 бита, полная точность.
--   Выход IP: 48-битная шина (дополнена до байта), значимые только младшие OUT_W бит
--   (43 бит для LPF, по Summary). Коэффициенты масштабированы на 2**SHIFT,
--   поэтому выход делится на 2**SHIFT (арифметический сдвиг вправо) и ограничивается
--   (насыщение) до 24 бит со знаком.
--
-- Сдвиг: 18 для LPF (при 16-битных коэффициентах из design_filters.m).
--        Если перейдёте на 18-битные коэффициенты: LPF -> 20, HPF -> 17.
--
-- Тайминг: IP вычисляет отсчёт около 137 тактов (1,4 мкс при 100 МГц), результат
-- приходит импульсом o_val в пределах того же периода дискретизации (~2083 такта).
-- Групповая задержка фильтра 64 отсчёта (1,33 мс, линейная фаза).
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity eq_lpf is
  generic (
    SHIFT : natural  := 18;    -- масштаб коэффициентов 2**SHIFT
    OUT_W : positive := 43     -- значимая ширина выхода IP (Summary: Output Width)
  );
  port (
    i_clk : in  std_logic;                       -- 100 МГц
    i_val : in  std_logic;                       -- строб нового отсчёта
    i_dat : in  std_logic_vector(23 downto 0);   -- знаковый отсчёт
    o_val : out std_logic := '0';                -- 1 такт, когда готов отфильтрованный отсчёт
    o_dat : out std_logic_vector(23 downto 0) := (others => '0')
  );
end eq_lpf;

architecture Behavioral of eq_lpf is

  -- объявление скопировано из fir_lpf_129t_b16.vho
  COMPONENT fir_lpf_129t_b16
    PORT (
      aclk               : IN  STD_LOGIC;
      s_axis_data_tvalid : IN  STD_LOGIC;
      s_axis_data_tready : OUT STD_LOGIC;
      s_axis_data_tdata  : IN  STD_LOGIC_VECTOR(23 DOWNTO 0);
      m_axis_data_tvalid : OUT STD_LOGIC;
      m_axis_data_tdata  : OUT STD_LOGIC_VECTOR(47 DOWNTO 0)
    );
  END COMPONENT;

  signal val_d   : std_logic := '0';
  signal s_valid : std_logic := '0';
  signal s_data  : std_logic_vector(23 downto 0) := (others => '0');
  signal s_ready : std_logic;
  signal m_valid : std_logic;
  signal m_data  : std_logic_vector(47 downto 0);

begin

  assert OUT_W >= 25 and OUT_W <= 48
    report "eq_lpf: OUT_W должен быть в диапазоне 25..48" severity failure;

  -- при периоде отсчётов ~2083 такта IP всегда готов принять отсчёт
  assert not (s_valid = '1' and s_ready = '0')
    report "eq_lpf: FIR не готов принять отсчёт (отсчёт потерян)" severity warning;

  i_fir : fir_lpf_129t_b16
    port map (
      aclk               => i_clk,
      s_axis_data_tvalid => s_valid,
      s_axis_data_tready => s_ready,
      s_axis_data_tdata  => s_data,
      m_axis_data_tvalid => m_valid,
      m_axis_data_tdata  => m_data
    );

  main_proc : process(i_clk)
    variable v : signed(OUT_W-1 downto 0);
  begin
    if rising_edge(i_clk) then
      -- вход: один импульс на фронт i_val, данные фиксируются в тот же такт
      val_d   <= i_val;
      if i_val = '1' and val_d = '0' then   -- 'U'/'X' на входе трактуются как '0' (защита IP)
        s_valid <= '1';
      else
        s_valid <= '0';
      end if;
      s_data  <= i_dat;

      -- выход: нормировка (сдвиг) и насыщение до 24 бит
      o_val <= '0';
      if m_valid = '1' then
        v := shift_right(signed(m_data(OUT_W-1 downto 0)), SHIFT);
        if v > to_signed(8388607, OUT_W) then
          o_dat <= x"7FFFFF";
        elsif v < to_signed(-8388608, OUT_W) then
          o_dat <= x"800000";
        else
          o_dat <= std_logic_vector(v(23 downto 0));
        end if;
        o_val <= '1';
      end if;
    end if;
  end process;

end Behavioral;