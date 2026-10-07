----------------------------------------------------------------------------------
-- fx_ctrl.vhd - системное управление: сброс по включению, включение эффекта, реле обхода
--
-- 1) Сброс по включению (o_rst). Снимается, когда
--      * MMCM захватил частоту (i_locked = '1') и
--      * кодек "жив": подряд READY_SAMPLES раз строб i_tick (new_sample) приходил с
--        интервалом GAP_MIN..GAP_MAX тактов (то есть LRCLK 48 кГц стабилен; кодек
--        выдаёт LRCLK только после того, как скрипт I2C настроил его).
--    Исчезновение отсчётов (больше GAP_LIMIT тактов) или i_force_rst возвращают сброс.
--
-- 2) Включение эффекта по импульсу i_toggle (ножной переключатель после антидребезга).
--    При HAS_RELAY = true (плата педали), реле обесточено = обход (true bypass):
--      выкл -> вкл : flush линии задержки, реле включается, пауза RELAY_MS мс (дребезг
--                    контактов), затем мастер-уровень o_master плавно растёт до 256 (~5 мс);
--      вкл -> выкл : o_master плавно падает до 0 (ЦАП утихает), только потом реле
--                    отпускается, пауза RELAY_MS мс, o_fx_on = '0'.
--    Так реле коммутируется при заглушенном ЦАП, щелчков нет.
--    При HAS_RELAY = false (ZedBoard) реле нет: o_master = 256, эффект просто
--    включается/выключается (микс уходит в 0 в ядре), при включении делается flush.
--    START_ON = true: эффект включается автоматически после снятия сброса.
--
-- o_master (0..256) умножает уровни dry и wet в ядре; изменяется по i_tick (48 кГц).
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity fx_ctrl is
  generic (
    HAS_RELAY     : boolean  := true;
    START_ON      : boolean  := false;
    CLK_HZ        : positive := 100_000_000;
    RELAY_MS      : positive := 10;      -- время переключения/успокоения реле
    READY_SAMPLES : positive := 2400;    -- сколько подряд верных отсчётов нужно (50 мс)
    GAP_MIN       : positive := 2070;    -- допустимый интервал между отсчётами, тактов
    GAP_MAX       : positive := 2100;
    GAP_LIMIT     : positive := 4096     -- пропадание отсчётов
  );
  port (
    i_clk       : in  std_logic;
    i_locked    : in  std_logic;                       -- MMCM locked
    i_tick      : in  std_logic;                       -- new_sample
    i_force_rst : in  std_logic;                       -- принудительный сброс (кнопка), '0' если не нужен
    i_toggle    : in  std_logic;                       -- импульс: переключить эффект
    o_rst       : out std_logic;                       -- сброс для остальной логики
    o_ready     : out std_logic;                       -- кодек готов
    o_fx_on     : out std_logic;                       -- эффект включён
    o_relay     : out std_logic;                       -- '1' = реле включено (эффект), '0' = обход
    o_led       : out std_logic;
    o_master    : out std_logic_vector(8 downto 0);    -- общий уровень выхода 0..256
    o_flush     : out std_logic                        -- импульс очистки линии задержки
  );
end fx_ctrl;

architecture Behavioral of fx_ctrl is

  constant CLK_PER_MS : positive := CLK_HZ / 1000;

  type state_t is (ST_OFF, ST_ON_WAIT, ST_ON, ST_OFF_FADE, ST_OFF_WAIT);
  signal st : state_t := ST_OFF;

  signal good     : natural range 0 to READY_SAMPLES := 0;
  signal gap      : natural range 0 to GAP_LIMIT := 0;
  signal ready_c  : std_logic;
  signal rst_r    : std_logic := '1';
  signal fx_on_r  : std_logic := '0';
  signal relay_r  : std_logic := '0';
  signal flush_r  : std_logic := '0';
  signal started  : std_logic := '0';
  signal ms_cnt   : natural range 0 to CLK_PER_MS-1 := 0;
  signal wait_ms  : natural range 0 to RELAY_MS := 0;
  signal master_tgt : std_logic_vector(8 downto 0) := (others => '0');
  signal master_s   : std_logic_vector(8 downto 0);

begin

  ready_c <= '1' when good >= READY_SAMPLES else '0';

  -- контроль наличия стабильных отсчётов 48 кГц
  mon_proc : process(i_clk)
  begin
    if rising_edge(i_clk) then
      if i_tick = '1' then
        if gap >= GAP_MIN and gap <= GAP_MAX then
          if good < READY_SAMPLES then
            good <= good + 1;
          end if;
        else
          good <= 0;
        end if;
        gap <= 1;
      else
        if gap < GAP_LIMIT then
          gap <= gap + 1;
        else
          good <= 0;
        end if;
      end if;
      if i_force_rst = '1' then
        good <= 0;
      end if;
    end if;
  end process;

  -- плавное изменение общего уровня
  i_master_slew : entity work.slew
    generic map (WIDTH => 9, STEP => 1, DIV => 1)
    port map (i_clk => i_clk, i_rst => rst_r, i_tick => i_tick,
              i_target => master_tgt, o_value => master_s);

  fsm_proc : process(i_clk)
    variable req : std_logic;
  begin
    if rising_edge(i_clk) then
      rst_r   <= not (ready_c and i_locked);
      flush_r <= '0';

      if rst_r = '1' then
        st         <= ST_OFF;
        fx_on_r    <= '0';
        relay_r    <= '0';
        master_tgt <= (others => '0');
        started    <= '0';
        ms_cnt     <= 0;
        wait_ms    <= 0;
      else
        req := i_toggle;
        if START_ON and started = '0' then
          req     := '1';
          started <= '1';
        end if;
        if not HAS_RELAY then
          master_tgt <= std_logic_vector(to_unsigned(256, 9));
        end if;

        case st is

          when ST_OFF =>
            if req = '1' then
              flush_r <= '1';
              fx_on_r <= '1';
              if HAS_RELAY then
                relay_r <= '1';
                ms_cnt  <= 0;
                wait_ms <= 0;
                st      <= ST_ON_WAIT;
              else
                st <= ST_ON;
              end if;
            end if;

          when ST_ON_WAIT =>             -- ждём успокоения контактов, потом включаем звук
            if ms_cnt = CLK_PER_MS-1 then
              ms_cnt <= 0;
              if wait_ms < RELAY_MS then
                wait_ms <= wait_ms + 1;
              end if;
            else
              ms_cnt <= ms_cnt + 1;
            end if;
            if wait_ms = RELAY_MS then
              master_tgt <= std_logic_vector(to_unsigned(256, 9));
              st         <= ST_ON;
            end if;

          when ST_ON =>
            if req = '1' then
              if HAS_RELAY then
                master_tgt <= (others => '0');
                st         <= ST_OFF_FADE;
              else
                fx_on_r <= '0';
                st      <= ST_OFF;
              end if;
            end if;

          when ST_OFF_FADE =>            -- ждём, пока ЦАП утихнет, и только потом отпускаем реле
            if unsigned(master_s) = 0 then
              relay_r <= '0';
              ms_cnt  <= 0;
              wait_ms <= 0;
              st      <= ST_OFF_WAIT;
            end if;

          when ST_OFF_WAIT =>
            if ms_cnt = CLK_PER_MS-1 then
              ms_cnt <= 0;
              if wait_ms < RELAY_MS then
                wait_ms <= wait_ms + 1;
              end if;
            else
              ms_cnt <= ms_cnt + 1;
            end if;
            if wait_ms = RELAY_MS then
              fx_on_r <= '0';
              st      <= ST_OFF;
            end if;

        end case;
      end if;
    end if;
  end process;

  o_rst    <= rst_r;
  o_ready  <= ready_c;
  o_fx_on  <= fx_on_r;
  o_relay  <= relay_r;
  o_led    <= relay_r when HAS_RELAY else fx_on_r;
  o_master <= master_s;
  o_flush  <= flush_r;

end Behavioral;