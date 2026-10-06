library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;


entity button is
  generic(
       FCLK                 : real := 50.0e6; -- Clock Frequency Hz
       SHORT_PRESS_DURATION : real := 0.1;    -- seconds
       LONG_PRESS_DURATION  : real := 1.0     -- seconds
       );
  port(
       i_clk   : in  std_logic;
       i_press : in  std_logic;
       o_short : out std_logic;
       o_long  : out std_logic
       );
end button;


architecture arch of button is
-- Constants
  constant SHORT_PRESS_DURATION_INT : positive := positive(round(SHORT_PRESS_DURATION * FCLK));
  constant LONG_PRESS_DURATION_INT  : positive := positive(round(LONG_PRESS_DURATION * FCLK));
  constant CNT_WIDTH : positive := positive(ceil(log2(LONG_PRESS_DURATION * FCLK +1.0)));
  constant MAX_DURATION_INT : unsigned(CNT_WIDTH -1 downto 0) := (others => '1');


-- Signals
  signal cnt : unsigned(CNT_WIDTH -1 downto 0) := (others => '0');


begin

  CNT_proc : process( i_clk )
  begin
       if rising_edge(i_clk) then
          if not i_press = '1' then
            cnt <= (others => '0');
          elsif cnt < MAX_DURATION_INT then
            cnt <= cnt +1;
          end if;
       end if;
  end process;


  SHORT_PRESS_proc : process( i_clk )
  begin
       if rising_edge(i_clk) then
          if cnt = SHORT_PRESS_DURATION_INT then
            o_short <= '1';
          else
            o_short <= '0';
          end if;
       end if;
  end process;


  LONG_PRESS_proc : process( i_clk )
  begin
       if rising_edge(i_clk) then
         if cnt = LONG_PRESS_DURATION_INT then
            o_long <= '1';
         else
            o_long <= '0';
         end if;
       end if;
  end process;


end arch;