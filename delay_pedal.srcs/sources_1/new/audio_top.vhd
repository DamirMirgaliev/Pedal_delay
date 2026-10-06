library IEEE;
use IEEE.STD_LOGIC_1164.ALL;


entity audio_top is
  Port ( clk_100        : in    STD_LOGIC; -- 100 mhz input clock from top level logic
         AC_MCLK        : out   STD_LOGIC; -- 24 Mhz for ADAU1761
         AC_ADR0        : out   STD_LOGIC; -- I2C contol signals to ADAU1761, for configuration
         AC_ADR1        : out   STD_LOGIC;
         AC_SCK         : out   STD_LOGIC;
         AC_SDA         : inout STD_LOGIC;
         AC_GPIO0       : out   STD_LOGIC; -- I2S MISO
         AC_GPIO1       : in    STD_LOGIC; -- I2S MOSI
         AC_GPIO2       : in    STD_LOGIC; -- I2S_bclk
         AC_GPIO3       : in    STD_LOGIC; -- I2S_LR

         hphone_l       : in    STD_LOGIC_VECTOR(23 downto 0); -- samples to head phone jack
         hphone_l_valid : in    std_logic;
         hphone_r       : in    STD_LOGIC_VECTOR(23 downto 0);
         hphone_r_valid_dummy : in std_logic; -- dummy valid signal to create AXIS interface in Vivado (r and l channel synchronous to hphone_l_valid

         line_in_l      : out   STD_LOGIC_VECTOR(23 downto 0); -- samples from "line in" jack
         line_in_r      : out   STD_LOGIC_VECTOR(23 downto 0);

         o_clk_100      : out   std_logic;
         new_sample     : out   STD_LOGIC; -- active for 1 clk cycle if new "line in" sample is tranmitted/received
         sample_clk_48k : out   std_logic  -- sample clock (new sample at rising edge)
         );
end audio_top;


architecture Behavioral of audio_top is

  COMPONENT adau1761_izedboard
  PORT(
        clk_48     : IN    std_logic;
        AC_GPIO1   : IN    std_logic;
        AC_GPIO2   : IN    std_logic;
        AC_GPIO3   : IN    std_logic;
        hphone_l   : IN    std_logic_vector(23 downto 0);
        hphone_r   : IN    std_logic_vector(23 downto 0);
        AC_SDA     : INOUT std_logic;
        AC_ADR0    : OUT   std_logic;
        AC_ADR1    : OUT   std_logic;
        AC_GPIO0   : OUT   std_logic;
        AC_MCLK    : OUT   std_logic;
        AC_SCK     : OUT   std_logic;
        line_in_l  : OUT   std_logic_vector(23 downto 0);
        line_in_r  : OUT   std_logic_vector(23 downto 0);
        new_sample : out   std_logic;
        sw         : in    std_logic_vector(1 downto 0);
        active     : out   std_logic_vector(1 downto 0)
        );
  END COMPONENT;


  -- generates 48 MHz (internal) out of 100 MHz (external clock)
  component clocking
  port(
       CLK_100   : in  std_logic;
       o_CLK_100 : out std_logic;
       CLK_48    : out std_logic;
       RESET     : in  std_logic;
       LOCKED    : out std_logic
       );
  end component;


  signal clk_48           : std_logic; -- this is the master clock (48Mhz) of the design
  signal new_sample_100   : std_logic; -- new_samples signal in the 100 MHz domain
  signal line_in_l_freeze_48, line_in_r_freeze_48: STD_LOGIC_VECTOR(23 downto 0); -- "line in" signals from I2S receiver to external interface (are freezed by the I2S receiver)
  signal sample_clk_48k_d1_48, sample_clk_48k_d2_48, sample_clk_48k_d3_48: std_logic; -- delay and synchronization registers for the sample clock (48k)
  signal sample_clk_48k_d4_100, sample_clk_48k_d5_100, sample_clk_48k_d6_100 : std_logic;
  signal hphone_l_freeze_100, hphone_r_freeze_100: STD_LOGIC_VECTOR(23 downto 0); -- for CDC 100 -> 48 Mhz freeze registers
  signal hphone_valid     : std_logic; -- internal signal for hphone_l_valid
  signal clk_100_bufg     : std_logic;
  attribute DONT_TOUCH : string;
  attribute DONT_TOUCH of clk_100_bufg : signal is "true";
  attribute DONT_TOUCH of new_sample   : signal is "true";
begin

  -- converts 100 mhz input into 48 mhz clk
  i_clocking : clocking port map (
       CLK_100   => clk_100,
       o_CLK_100 => clk_100_bufg,
       CLK_48    => clk_48,
       RESET     => '0',
       LOCKED    => open
  );
  o_clk_100 <= clk_100_bufg;

  Inst_adau1761_izedboard: adau1761_izedboard PORT MAP(
       clk_48     => clk_48,
       AC_ADR0    => AC_ADR0,
       AC_ADR1    => AC_ADR1,
       AC_GPIO0   => AC_GPIO0,
       AC_GPIO1   => AC_GPIO1,
       AC_GPIO2   => AC_GPIO2,
       AC_GPIO3   => AC_GPIO3,
       AC_MCLK    => AC_MCLK,
       AC_SCK     => AC_SCK,
       AC_SDA     => AC_SDA,
       hphone_l   => hphone_l_freeze_100,
       hphone_r   => hphone_r_freeze_100,
       line_in_l  => line_in_l_freeze_48,
       line_in_r  => line_in_r_freeze_48,
       new_sample => open, -- new_sample is generated in the correct clock domain
       sw         => (others => '0'), -- all swichtes signals are tied to 0
       active     => open
  );


  hphone_valid <= hphone_l_valid; -- hphone_l_valid is "master" valid for hphone

  -- 3 registers for input of L/R clock (sample clock) for synch and delay
  process (clk_48)
  begin
       if (clk_48'event and clk_48 = '1') then
          sample_clk_48k_d1_48 <= AC_GPIO3;
          sample_clk_48k_d2_48 <= sample_clk_48k_d1_48;
          sample_clk_48k_d3_48 <= sample_clk_48k_d2_48;
       end if;
  end process;

  -- four registers for sample clk (synchronization and edge detection) in the 100 MHz domain
  -- and generation of a new new_sample signal in the 100 MHz domain (new_sample_100)
  process (clk_100_bufg)
  begin
  if rising_edge(clk_100_bufg) then
          sample_clk_48k_d4_100 <= sample_clk_48k_d3_48; -- ff1 & 2 for synchronization
          sample_clk_48k_d5_100 <= sample_clk_48k_d4_100;
          sample_clk_48k_d6_100 <= sample_clk_48k_d5_100; -- ff3 for edge detection
          sample_clk_48k        <= sample_clk_48k_d6_100; -- additional FF for signal delay (alignment to data)
          if (sample_clk_48k_d5_100 = '1' and sample_clk_48k_d6_100 = '0') then
             new_sample_100 <= '1';
          else
             new_sample_100 <= '0';
          end if;
          new_sample <= new_sample_100; -- additional FF for signal delay (alignment to data)
       end if;
  end process;


  -- 2) hphone audio data (l&r) CDC 100 MHz -> 48 MHz
  -- freeze FF to keep data before CDC
  process (clk_100_bufg)
  begin
       if (clk_100_bufg'event and clk_100_bufg = '1') then
          if (hphone_valid = '1') then
             hphone_l_freeze_100 <= hphone_l;
             hphone_r_freeze_100 <= hphone_r;
          end if;
       end if;
  end process;

  -- 3) line_in audio data: CDC 48 MHz -> 100 MHz
  -- line_in_l/r_freeze is already freezed as designed in the I2S receiver (i2s_data_interface)
  process (clk_100_bufg)
  begin
       if (clk_100_bufg'event and clk_100_bufg = '1') then
          if (new_sample_100 = '1') then
             line_in_l <= line_in_l_freeze_48;
             line_in_r <= line_in_r_freeze_48;
          end if;
       end if;
  end process;


end Behavioral;