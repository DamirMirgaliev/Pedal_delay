
//------------------------------------------------------------------------------
// (c) Copyright 2014 Xilinx, Inc. All rights reserved.
//
// This file contains confidential and proprietary information
// of Xilinx, Inc. and is protected under U.S. and
// international copyright and other intellectual property
// laws.
//
// DISCLAIMER
// This disclaimer is not a license and does not grant any
// rights to the materials distributed herewith. Except as
// otherwise provided in a valid license issued to you by
// Xilinx, and to the maximum extent permitted by applicable
// law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
// WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
// AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
// BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
// INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
// (2) Xilinx shall not be liable (whether in contract or tort,
// including negligence, or under any other theory of
// liability) for any loss or damage of any kind or nature
// related to, arising under or in connection with these
// materials, including for any direct, or any indirect,
// special, incidental, or consequential loss or damage
// (including loss of data, profits, goodwill, or any type of
// loss or damage suffered as a result of any action brought
// by a third party) even if such damage or loss was
// reasonably foreseeable or Xilinx had been advised of the
// possibility of the same.
//
// CRITICAL APPLICATIONS
// Xilinx products are not designed or intended to be fail-
// safe, or for use in any application requiring fail-safe
// performance, such as life-support or safety devices or
// systems, Class III medical devices, nuclear facilities,
// applications related to the deployment of airbags, or any
// other applications that could lead to death, personal
// injury, or severe property or environmental damage
// (individually and collectively, "Critical
// Applications"). Customer assumes the sole risk and
// liability of any use of Xilinx products in Critical
// Applications, subject only to applicable laws and
// regulations governing limitations on product liability.
//
// THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
// PART OF THIS FILE AT ALL TIMES.
//------------------------------------------------------------------------------ 
//
// C Model configuration for the "fir_lpf_129t_b16" instance.
//
//------------------------------------------------------------------------------
//
// coefficients: 0,0,0,0,0,0,0,0,0,0,1,1,2,3,4,5,7,8,9,9,8,3,-4,-16,-33,-54,-78,-102,-123,-136,-135,-113,-64,17,129,271,431,595,739,838,859,774,559,199,-304,-928,-1629,-2341,-2976,-3431,-3595,-3361,-2639,-1366,482,2883,5762,8996,12418,15827,19010,21754,23868,25201,25656,25201,23868,21754,19010,15827,12418,8996,5762,2883,482,-1366,-2639,-3361,-3595,-3431,-2976,-2341,-1629,-928,-304,199,559,774,859,838,739,595,431,271,129,17,-64,-113,-135,-136,-123,-102,-78,-54,-33,-16,-4,3,8,9,9,8,7,5,4,3,2,1,1,0,0,0,0,0,0,0,0,0,0
// chanpats: 173
// name: fir_lpf_129t_b16
// filter_type: 0
// rate_change: 0
// interp_rate: 1
// decim_rate: 1
// zero_pack_factor: 1
// coeff_padding: 0
// num_coeffs: 129
// coeff_sets: 1
// reloadable: 0
// is_halfband: 0
// quantization: 0
// coeff_width: 16
// coeff_fract_width: 0
// chan_seq: 0
// num_channels: 1
// num_paths: 1
// data_width: 24
// data_fract_width: 0
// output_rounding_mode: 0
// output_width: 43
// output_fract_width: 0
// config_method: 0

const double fir_lpf_129t_b16_coefficients[129] = {0,0,0,0,0,0,0,0,0,0,1,1,2,3,4,5,7,8,9,9,8,3,-4,-16,-33,-54,-78,-102,-123,-136,-135,-113,-64,17,129,271,431,595,739,838,859,774,559,199,-304,-928,-1629,-2341,-2976,-3431,-3595,-3361,-2639,-1366,482,2883,5762,8996,12418,15827,19010,21754,23868,25201,25656,25201,23868,21754,19010,15827,12418,8996,5762,2883,482,-1366,-2639,-3361,-3595,-3431,-2976,-2341,-1629,-928,-304,199,559,774,859,838,739,595,431,271,129,17,-64,-113,-135,-136,-123,-102,-78,-54,-33,-16,-4,3,8,9,9,8,7,5,4,3,2,1,1,0,0,0,0,0,0,0,0,0,0};

const xip_fir_v7_2_pattern fir_lpf_129t_b16_chanpats[1] = {P_BASIC};

static xip_fir_v7_2_config gen_fir_lpf_129t_b16_config() {
  xip_fir_v7_2_config config;
  config.name                = "fir_lpf_129t_b16";
  config.filter_type         = 0;
  config.rate_change         = XIP_FIR_INTEGER_RATE;
  config.interp_rate         = 1;
  config.decim_rate          = 1;
  config.zero_pack_factor    = 1;
  config.coeff               = &fir_lpf_129t_b16_coefficients[0];
  config.coeff_padding       = 0;
  config.num_coeffs          = 129;
  config.coeff_sets          = 1;
  config.reloadable          = 0;
  config.is_halfband         = 0;
  config.quantization        = XIP_FIR_INTEGER_COEFF;
  config.coeff_width         = 16;
  config.coeff_fract_width   = 0;
  config.chan_seq            = XIP_FIR_BASIC_CHAN_SEQ;
  config.num_channels        = 1;
  config.init_pattern        = fir_lpf_129t_b16_chanpats[0];
  config.num_paths           = 1;
  config.data_width          = 24;
  config.data_fract_width    = 0;
  config.output_rounding_mode= XIP_FIR_FULL_PRECISION;
  config.output_width        = 43;
  config.output_fract_width  = 0,
  config.config_method       = XIP_FIR_CONFIG_SINGLE;
  return config;
}

const xip_fir_v7_2_config fir_lpf_129t_b16_config = gen_fir_lpf_129t_b16_config();

