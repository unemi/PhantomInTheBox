#! /bin/zsh
awk '{split($3,a,",");split(a[2],b,"=");x[$1]=b[2]}
END{for(i=1;i<=10;i++)printf " & %d",i; print "\\\\ \\hline";
printf "Horizontal size";for(i=1;i<=10;i++)printf " & %.1f",x[i]; print "\\\\";
printf "Vertical size";for(i=1;i<=10;i++)printf " & %.1f",x[i]*9/16; print "\\\\";
printf "Depth size";for(i=1;i<=10;i++)printf " & %.1f",x[i]*12/16; print "\\\\"}' < CompTM_4500.dat

