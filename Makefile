BSC=bsc
BSCOPTS=-u -sim -check-assert

all: testTUEBenchmark

testTUEBenchmark: TUEBenchmark.bo
	$(BSC) -e mkTUEBenchmark -o testTUEBenchmark $(BSCOPTS)

%.bo: %.bsv
	$(BSC) $(BSCOPTS) $<

.PHONY: clean

clean:
	rm -rf *~ # Kill emacs backup files
	rm -rf *.bo mk*.v *.sched testTUEBenchmark.so schedule.* imported_BDPI_functions.h mkTUEBenchmark.* # Generated Bluespec files
	rm -rf testTUEBenchmark *.log *.cmd *.xmsgs *.wdb *.tcl *.isim isim# ISim files