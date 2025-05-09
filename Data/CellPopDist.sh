#! /bin/zsh
awk -F, 'BEGIN{s=10}
{i=int($2/s);c[i]++;if(i>m)m=i}
END{for(i=0;i<=m;i++)printf "%d %.5f\n",(i+0.5)*s,c[i]*100/NR}'\
 CellPopDist.csv > CellPopHist.dat
m=`tail -1 CellPopHist.dat | cut -d\  -f1`
gnuplot << EOF > CellPopDist.pdf
set term pdf font "Serif,20"
unset key
set logscale y
set xrange [0:$((m+5))]
set yrange [0.005:100]
set xlabel "The number of individuals in a partition"
set ylabel "Percentage of partitions"
set boxwidth 0.6 relative
set style fill solid
plot 'CellPopHist.dat' with boxes fc "#55555588"
EOF
