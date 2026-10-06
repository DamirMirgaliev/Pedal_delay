onbreak {quit -force}
onerror {quit -force}

asim +access +r +m+fifo_delay_axis -L xpm -L axis_infrastructure_v1_1_0 -L axis_data_fifo_v2_0_8 -L xil_defaultlib -L unisims_ver -L unimacro_ver -L secureip -O5 xil_defaultlib.fifo_delay_axis xil_defaultlib.glbl

set NumericStdNoWarnings 1
set StdArithNoWarnings 1

do {wave.do}

view wave
view structure

do {fifo_delay_axis.udo}

run -all

endsim

quit -force
