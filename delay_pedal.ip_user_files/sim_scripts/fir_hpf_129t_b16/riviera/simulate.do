onbreak {quit -force}
onerror {quit -force}

asim +access +r +m+fir_hpf_129t_b16 -L xpm -L xbip_utils_v3_0_10 -L axi_utils_v2_0_6 -L fir_compiler_v7_2_18 -L xil_defaultlib -L unisims_ver -L unimacro_ver -L secureip -O5 xil_defaultlib.fir_hpf_129t_b16 xil_defaultlib.glbl

set NumericStdNoWarnings 1
set StdArithNoWarnings 1

do {wave.do}

view wave
view structure

do {fir_hpf_129t_b16.udo}

run -all

endsim

quit -force
