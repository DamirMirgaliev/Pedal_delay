# =============================================================================
# zed_audio.xdc - ограничения проекта delay_pedal (ZedBoard, xc7z020clg484-1)
# =============================================================================

# ---------------------------- тактовый сигнал --------------------------------
# 100 МГц от генератора платы (период 10 нс). Определение ТОЛЬКО ОДНО.
create_clock -period 10.000 -name clk_100 [get_ports clk_100]

# --------------------- пересечение доменов 100 МГц <-> 48 МГц -----------------
# Данные между доменами передаются через "замороженные" регистры и синхронизаторы
# (см. audio_top.vhd), поэтому анализ этих путей отключаем в обе стороны.
# Тактовый сигнал zed_audio_clk_48M создаётся модулем clocking.
set_false_path -from [get_clocks zed_audio_clk_48M] -to [get_clocks clk_100]
set_false_path -from [get_clocks clk_100] -to [get_clocks zed_audio_clk_48M]

# ------------------------------ расположение выводов --------------------------
# 100 mhz clock
set_property PACKAGE_PIN Y9 [get_ports clk_100]
set_property IOSTANDARD LVCMOS33 [get_ports clk_100]

# 24 mhz clock to audio chip
set_property PACKAGE_PIN AB2 [get_ports AC_MCLK]
set_property IOSTANDARD LVCMOS33 [get_ports AC_MCLK]


# I2S transfers audio samples
# i2s data to ADAU1761
set_property PACKAGE_PIN Y8 [get_ports AC_GPIO0]
set_property IOSTANDARD LVCMOS33 [get_ports AC_GPIO0]

# i2s data from ADAU1761
set_property PACKAGE_PIN AA7 [get_ports AC_GPIO1]
set_property IOSTANDARD LVCMOS33 [get_ports AC_GPIO1]

# i2s bit clock from ADAU1761
set_property PACKAGE_PIN AA6 [get_ports AC_GPIO2]
set_property IOSTANDARD LVCMOS33 [get_ports AC_GPIO2]

# i2s l/r 48 khz toggling signal from ADAU1761 (sample clock)
set_property PACKAGE_PIN Y6 [get_ports AC_GPIO3]
set_property IOSTANDARD LVCMOS33 [get_ports AC_GPIO3]


# I2C Data Interface to ADAU1761 (for configuration)
set_property PACKAGE_PIN AB4 [get_ports AC_SCK]
set_property IOSTANDARD LVCMOS33 [get_ports AC_SCK]

set_property PACKAGE_PIN AB5 [get_ports AC_SDA]
set_property IOSTANDARD LVCMOS33 [get_ports AC_SDA]

set_property PACKAGE_PIN AB1 [get_ports AC_ADR0]
set_property IOSTANDARD LVCMOS33 [get_ports AC_ADR0]

set_property PACKAGE_PIN Y5 [get_ports AC_ADR1]
set_property IOSTANDARD LVCMOS33 [get_ports AC_ADR1]


# Knopka central
set_property PACKAGE_PIN P16 [get_ports BTNC]
set_property IOSTANDARD LVCMOS33 [get_ports BTNC]

# Knopka up
set_property PACKAGE_PIN T18 [get_ports BTNU]
set_property IOSTANDARD LVCMOS33 [get_ports BTNU]

# Knopka down
set_property PACKAGE_PIN R16 [get_ports BTND]
set_property IOSTANDARD LVCMOS33 [get_ports BTND]

# Knopka left
set_property PACKAGE_PIN N15 [get_ports BTNL]
set_property IOSTANDARD LVCMOS33 [get_ports BTNL]

# Knopka right
set_property PACKAGE_PIN R18 [get_ports BTNR]
set_property IOSTANDARD LVCMOS33 [get_ports BTNR]
