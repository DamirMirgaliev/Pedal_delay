----------------------------------------------------------------------------------
-- delay_line.vhd  (ранее fifo_delay.vhd)
-- Линия задержки аудиосигнала на AXI4-Stream FIFO (fifo_delay_axis, 32 бита, 32768).
--
-- Принцип: на каждый новый отсчёт (i_val) отсчёт записывается в FIFO. Когда в FIFO уже
-- накоплено не меньше i_delay отсчётов, на каждый новый отсчёт из FIFO читается самый
-- старый -> он был записан ровно i_delay отсчётов назад.
-- Задержка = i_delay / Fs, при Fs = 48 кГц: 32000 отсчётов = 0,667 с.
--
-- Всё работает в одном домене i_clk (100 МГц). Количество отсчётов в FIFO считается
-- внутри модуля (счётчик fill), порт axis_data_count у IP не нужен.
--
-- Изменение i_delay "на лету":
--   * задержка увеличилась  -> пока FIFO не наполнится до нового значения, на выходе 0;
--   * задержка уменьшилась  -> лишние отсчёты вычитываются и отбрасываются (по одному
--                              лишнему за каждый новый отсчёт).
-- Поэтому значение с потенциометра нужно сглаживать/ограничивать по скорости.
--
-- i_flush (импульс): очищает линию задержки (FIFO и счётчик заполнения). Сброс FIFO
-- удерживается 16 тактов; новые отсчёты в это время игнорируются.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity delay_line is
  generic (
    DAT_WIDTH : positive := 24;      -- разрядность отсчёта (<= 32)
    MAX_DELAY : positive := 32000;   -- максимум, отсчётов (должен быть < глубины FIFO 32768)
    MIN_DELAY : positive := 8        -- минимум, отсчётов
  );
  port (
    i_clk   : in  std_logic;
    i_rst   : in  std_logic;                                -- активный уровень '1'
    i_flush : in  std_logic := '0';                         -- импульс: очистить линию задержки
    i_val   : in  std_logic;                                -- строб нового отсчёта
    i_dat   : in  std_logic_vector(DAT_WIDTH-1 downto 0);   -- знаковый отсчёт
    i_delay : in  std_logic_vector(15 downto 0);            -- задержка в отсчётах
    o_val   : out std_logic := '0';                         -- 1 такт на каждый новый отсчёт
    o_dat   : out std_logic_vector(DAT_WIDTH-1 downto 0) := (others => '0')
  );
end delay_line;

architecture Behavioral of delay_line is

  -- объявление скопировано из fifo_delay_axis.vho
  COMPONENT fifo_delay_axis
    PORT (
      s_axis_aresetn : IN STD_LOGIC;
      s_axis_aclk    : IN STD_LOGIC;
      s_axis_tvalid  : IN STD_LOGIC;
      s_axis_tready  : OUT STD_LOGIC;
      s_axis_tdata   : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
      m_axis_tvalid  : OUT STD_LOGIC;
      m_axis_tready  : IN STD_LOGIC;
      m_axis_tdata   : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
    );
  END COMPONENT;

  signal val_d       : std_logic := '0';
  signal s_tvalid    : std_logic := '0';
  signal s_tready    : std_logic;
  signal s_tdata     : std_logic_vector(31 downto 0) := (others => '0');
  signal m_tvalid    : std_logic;
  signal m_tready    : std_logic;
  signal m_tdata     : std_logic_vector(31 downto 0);
  signal aresetn     : std_logic;
  signal flush_cnt   : natural range 0 to 15 := 0;            -- удержание сброса при flush
  signal rst_int     : std_logic;                             -- i_rst или идёт flush

  signal busy        : std_logic := '0';                  -- идёт чтение из FIFO
  signal pop_left    : unsigned(1 downto 0) := (others => '0');
  signal fill        : unsigned(15 downto 0) := (others => '0');  -- отсчётов в FIFO
  signal delay_eff   : unsigned(15 downto 0);

begin

  -- ограничение задержки диапазоном [MIN_DELAY, MAX_DELAY]
  delay_eff <= to_unsigned(MAX_DELAY, 16) when unsigned(i_delay) > MAX_DELAY else
               to_unsigned(MIN_DELAY, 16) when unsigned(i_delay) < MIN_DELAY else
               unsigned(i_delay);

  rst_int   <= '1' when (i_rst = '1' or flush_cnt /= 0) else '0';
  aresetn   <= not rst_int;
  m_tready  <= busy;

  i_fifo : fifo_delay_axis
    port map (
      s_axis_aresetn => aresetn,
      s_axis_aclk    => i_clk,
      s_axis_tvalid  => s_tvalid,
      s_axis_tready  => s_tready,
      s_axis_tdata   => s_tdata,
      m_axis_tvalid  => m_tvalid,
      m_axis_tready  => m_tready,
      m_axis_tdata   => m_tdata
    );

  flush_proc : process(i_clk)
  begin
    if rising_edge(i_clk) then
      if i_flush = '1' then
        flush_cnt <= 15;
      elsif flush_cnt /= 0 then
        flush_cnt <= flush_cnt - 1;
      end if;
    end if;
  end process;

  main_proc : process(i_clk)
    variable inc, dec : std_logic;
  begin
    if rising_edge(i_clk) then
      if rst_int = '1' then
        val_d    <= '0';
        s_tvalid <= '0';
        busy     <= '0';
        pop_left <= (others => '0');
        fill     <= (others => '0');
        o_val    <= '0';
        o_dat    <= (others => '0');
      else
        val_d    <= i_val;
        s_tvalid <= '0';
        o_val    <= '0';

        -- событие "новый отсчёт" (по фронту i_val)
        if i_val = '1' and val_d = '0' then
          s_tdata  <= std_logic_vector(resize(signed(i_dat), 32));  -- знаковое расширение
          s_tvalid <= '1';
          if fill >= delay_eff then
            if fill > delay_eff then
              pop_left <= to_unsigned(2, 2);   -- задержка уменьшилась: лишний отсчёт отбрасываем
            else
              pop_left <= to_unsigned(1, 2);
            end if;
            busy <= '1';
          else
            o_dat <= (others => '0');          -- FIFO ещё наполняется: тишина
            o_val <= '1';
          end if;
        end if;

        -- чтение из FIFO (рукопожатие AXI-Stream: tvalid and tready)
        dec := '0';
        if busy = '1' and m_tvalid = '1' then
          dec := '1';
          if pop_left = 1 then
            o_dat    <= m_tdata(DAT_WIDTH-1 downto 0);
            o_val    <= '1';
            busy     <= '0';
            pop_left <= (others => '0');
          else
            pop_left <= pop_left - 1;          -- этот отсчёт отбрасывается
          end if;
        end if;

        -- счётчик заполнения FIFO
        inc := s_tvalid and s_tready;
        if inc = '1' and dec = '0' then
          fill <= fill + 1;
        elsif inc = '0' and dec = '1' then
          fill <= fill - 1;
        end if;
      end if;
    end if;
  end process;

end Behavioral;