onbreak {quit -f}
onerror {quit -f}

vsim -lib xil_defaultlib fifo_delay_axis_opt

set NumericStdNoWarnings 1
set StdArithNoWarnings 1

do {wave.do}

view wave
view structure
view signals

do {fifo_delay_axis.udo}

run -all

quit -force
