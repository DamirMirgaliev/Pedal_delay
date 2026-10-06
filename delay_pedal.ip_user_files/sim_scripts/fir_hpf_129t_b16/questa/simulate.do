onbreak {quit -f}
onerror {quit -f}

vsim -lib xil_defaultlib fir_hpf_129t_b16_opt

set NumericStdNoWarnings 1
set StdArithNoWarnings 1

do {wave.do}

view wave
view structure
view signals

do {fir_hpf_129t_b16.udo}

run -all

quit -force
