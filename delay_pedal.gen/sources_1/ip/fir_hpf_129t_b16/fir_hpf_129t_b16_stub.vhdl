-- Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2022.1 (win64) Build 3526262 Mon Apr 18 15:48:16 MDT 2022
-- Date        : Tue Oct  6 05:48:02 2026
-- Host        : DESKTOP-CVLIU8H running 64-bit major release  (build 9200)
-- Command     : write_vhdl -force -mode synth_stub
--               d:/delay_pedal/delay_pedal/delay_pedal.gen/sources_1/ip/fir_hpf_129t_b16/fir_hpf_129t_b16_stub.vhdl
-- Design      : fir_hpf_129t_b16
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xc7z020clg484-1
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity fir_hpf_129t_b16 is
  Port ( 
    aclk : in STD_LOGIC;
    s_axis_data_tvalid : in STD_LOGIC;
    s_axis_data_tready : out STD_LOGIC;
    s_axis_data_tdata : in STD_LOGIC_VECTOR ( 23 downto 0 );
    m_axis_data_tvalid : out STD_LOGIC;
    m_axis_data_tdata : out STD_LOGIC_VECTOR ( 47 downto 0 )
  );

end fir_hpf_129t_b16;

architecture stub of fir_hpf_129t_b16 is
attribute syn_black_box : boolean;
attribute black_box_pad_pin : string;
attribute syn_black_box of stub : architecture is true;
attribute black_box_pad_pin of stub : architecture is "aclk,s_axis_data_tvalid,s_axis_data_tready,s_axis_data_tdata[23:0],m_axis_data_tvalid,m_axis_data_tdata[47:0]";
attribute x_core_info : string;
attribute x_core_info of stub : architecture is "fir_compiler_v7_2_18,Vivado 2022.1";
begin
end;
