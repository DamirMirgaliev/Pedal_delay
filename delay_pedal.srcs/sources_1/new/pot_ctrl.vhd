----------------------------------------------------------------------------------
-- pot_ctrl.vhd - обработка кодов потенциометров: усреднение, гистерезис, закон регулировки
--
-- Вход: результаты АЦП (12 бит) по одному каналу за раз (i_valid, i_chan, i_code),
-- например от xadc_pots. Каналы: 0 - время задержки, 1 - микс, 2 - уровень НЧ,
-- 3 - уровень ВЧ, 4 - обратная связь (необязательный пятый потенциометр, NUM_POTS = 5).
--
-- Обработка каждого канала:
--   1) среднее по 16 отсчётам (убирает шум АЦП и питания потенциометра);
--   2) гистерезис +-HYST кодов: значение меняется, только если среднее ушло дальше;
--      у крайних положений (0 и 4095) значение "прилипает" к краю;
--   3) закон регулировки (потенциометры линейные):
--        задержка: линейно DELAY_MIN..DELAY_MAX отсчётов;
--        микс:     линейно 0..256;
--        LP, HP, обратная связь: квадратичный закон (напоминает логарифмический,
--                  половина хода = 0,25 = -12 дБ), 0..256.
-- Выходы совпадают по формату с ctrl_buttons, ядро не отличает источники параметров.
-- Если потенциометра обратной связи нет (NUM_POTS = 4), o_fb = FB_DEFAULT.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity pot_ctrl is
  generic (
    NUM_POTS   : positive range 4 to 5 := 4;
    HYST       : natural := 3;
    DELAY_MIN  : natural := 73;
    DELAY_MAX  : natural := 32065;
    FB_DEFAULT : natural := 0;
    FB_MAX     : natural := 240
  );
  port (
    i_clk   : in  std_logic;
    i_rst   : in  std_logic;
    i_valid : in  std_logic;                        -- новый код АЦП
    i_chan  : in  std_logic_vector(2 downto 0);     -- номер потенциометра 0..4
    i_code  : in  std_logic_vector(11 downto 0);    -- 12-битный код
    o_delay : out std_logic_vector(15 downto 0);
    o_mix   : out std_logic_vector(8 downto 0);
    o_lp    : out std_logic_vector(8 downto 0);
    o_hp    : out std_logic_vector(8 downto 0);
    o_fb    : out std_logic_vector(8 downto 0)
  );
end pot_ctrl;

architecture Behavioral of pot_ctrl is

  constant SPAN : natural := DELAY_MAX - DELAY_MIN;

  type acc_t  is array (0 to 4) of unsigned(15 downto 0);
  type held_t is array (0 to 4) of unsigned(11 downto 0);
  type cnt_t  is array (0 to 4) of natural range 0 to 15;

  signal acc  : acc_t  := (others => (others => '0'));
  signal held : held_t := (others => (others => '0'));
  signal cnt  : cnt_t  := (others => 0);

  -- линейное преобразование 0..4095 -> 0..256
  function lin256(code : unsigned(11 downto 0)) return unsigned is
    variable p : unsigned(20 downto 0);
  begin
    p := code * to_unsigned(257, 9);
    return resize(shift_right(p, 12), 9);
  end function;

  -- квадратичный закон 0..256 -> 0..256
  function taper(l : unsigned(8 downto 0)) return unsigned is
    variable p : unsigned(17 downto 0);
  begin
    p := l * l;
    return resize(shift_right(p, 8), 9);
  end function;

begin

  -- усреднение и гистерезис
  filt_proc : process(i_clk)
    variable idx  : natural;
    variable s    : unsigned(15 downto 0);
    variable avg  : unsigned(11 downto 0);
    variable diff : integer;
  begin
    if rising_edge(i_clk) then
      if i_rst = '1' then
        acc  <= (others => (others => '0'));
        cnt  <= (others => 0);
        held <= (others => (others => '0'));
      elsif i_valid = '1' then
        idx := to_integer(unsigned(i_chan));
        if idx < NUM_POTS then
          s := acc(idx) + resize(unsigned(i_code), 16);
          if cnt(idx) = 15 then
            avg  := resize(shift_right(s, 4), 12);
            diff := to_integer(avg) - to_integer(held(idx));
            if to_integer(avg) >= 4095 - HYST then
              held(idx) <= to_unsigned(4095, 12);          -- прилипание к верхнему краю
            elsif to_integer(avg) <= HYST then
              held(idx) <= to_unsigned(0, 12);             -- прилипание к нижнему краю
            elsif diff > HYST or diff < -HYST then
              held(idx) <= avg;
            end if;
            acc(idx) <= (others => '0');
            cnt(idx) <= 0;
          else
            acc(idx) <= s;
            cnt(idx) <= cnt(idx) + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- закон регулировки
  map_proc : process(i_clk)
    variable d  : unsigned(26 downto 0);
    variable l  : unsigned(8 downto 0);
  begin
    if rising_edge(i_clk) then
      d := held(0) * to_unsigned(SPAN, 15);
      o_delay <= std_logic_vector(resize(shift_right(d, 12), 16) + DELAY_MIN);

      o_mix <= std_logic_vector(lin256(held(1)));
      o_lp  <= std_logic_vector(taper(lin256(held(2))));
      o_hp  <= std_logic_vector(taper(lin256(held(3))));

      if NUM_POTS = 5 then
        l := taper(lin256(held(4)));
        if l > FB_MAX then
          l := to_unsigned(FB_MAX, 9);
        end if;
        o_fb <= std_logic_vector(l);
      else
        o_fb <= std_logic_vector(to_unsigned(FB_DEFAULT, 9));
      end if;
    end if;
  end process;

end Behavioral;