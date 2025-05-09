#! /bin/zsh
gnuplot <<EOF > CompTM.pdf
set term pdf font "Serif,20" size 5,4
set xlabel "Population size (×10^5)"
set ylabel "Millisecond per step"
set xrange [0:11]
set style data linespoints
set key left
plot 'CompTM_12727.dat' title "{/Serif:Italic R_s} = 12.73",\
	'CompTM_9000.dat' title "{/Serif:Italic R_s} = 9.00",\
	'CompTM_6363.dat' title "{/Serif:Italic R_s} = 6.36",\
	'CompTM_4500.dat' title "{/Serif:Italic R_s} = 4.50"
EOF
