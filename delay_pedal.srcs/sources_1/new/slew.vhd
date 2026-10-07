----------------------------------------------------------------------------------
-- slew.vhd - ограничитель скорости изменения параметра (сглаживание)
--
-- На каждый DIV-й импульс i_tick (обычно new_sample, 48 кГц) значение o_value
-- приближается к i_target не более чем на STEP. Применения:
--   * уровни (микс, LP, HP, обратная связь): WIDTH = 9,  STEP = 1, DIV = 1
--       полный ход 0..256 за 256 отсчётов = 5,3 мс, нет "зиппер-шума" и щелчков;
--   * время задержки:                          WIDTH = 16, STEP = 1, DIV = 8
--       1 отсчёт за 8 отсчётов, как при вращении ручки на ленточном эхо
--       (высота плавает, но нет резких скачков). Полный ход ~5 с.
-- Пока i_rst = '1', выход повторяет цель (мгновенно).
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity slew is
  generic (
    WIDTH : positive := 9;
    STEP  : positive := 1;
    DIV   : positive := 1
  );
  port (
    i_clk    : in  std_logic;
    i_rst    : in  std_logic;
    i_tick   : in  std_logic;                              -- строб обновления (1 такт)
    i_target : in  std_logic_vector(WIDTH-1 downto 0);
    o_value  : out std_logic_vector(WIDTH-1 downto 0)
  );
end slew;

architecture Behavioral of slew is
  signal cur : unsigned(WIDTH-1 downto 0) := (others => '0');
  signal cnt : natural range 0 to DIV-1 := 0;
begin

  o_value <= std_logic_vector(cur);

  process(i_clk)
    variable tgt : unsigned(WIDTH-1 downto 0);
    variable stp : unsigned(WIDTH-1 downto 0);
  begin
    if rising_edge(i_clk) then
      tgt := unsigned(i_target);
      stp := to_unsigned(STEP, WIDTH);
      if i_rst = '1' then
        cur <= tgt;
        cnt <= 0;
      elsif i_tick = '1' then
        if cnt = DIV-1 then
          cnt <= 0;
          if cur < tgt then
            if (tgt - cur) > stp then
              cur <= cur + stp;
            else
              cur <= tgt;
            end if;
          elsif cur > tgt then
            if (cur - tgt) > stp then
              cur <= cur - stp;
            else
              cur <= tgt;
            end if;
          end if;
        else
          cnt <= cnt + 1;
        end if;
      end if;
    end if;
  end process;

end Behavioral;