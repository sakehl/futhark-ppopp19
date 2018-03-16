include config.mk

ifeq ($(FUTHARK_OPENCL_DEVICE),)
  DEVICE_OPTION=
else
  DEVICE_OPTION=--pass-option=-d$(FUTHARK_OPENCL_DEVICE)
endif

RODINIA_RUNS=10

FUTHARK_BENCH_OPENCL_OPTIONS=--compiler=$(FUTHARK_OPENCL) $(DEVICE_OPTION)

ifeq ($(FUTHARK_OPENCL),bin/futhark-opencl)
  FUTHARK_OPENCL_DEPS=bin/futhark-opencl
endif

ifeq ($(FUTHARK_C),bin/futhark-c)
  FUTHARK_C_DEPS=bin/futhark-c
endif

FUTHARK_AUTOTUNE=futhark/tools/futhark-autotune $(FUTHARK_BENCH_OPENCL_OPTIONS) --stop-after $(AUTOTUNE_SECONDS) --only threshold

.PHONY: all clean veryclean
.SECONDARY:

all: plots

plots: matmul-runtimes-large.pdf matmul-runtimes-small.pdf fft-runtimes.pdf LocVolCalib-runtimes.pdf bulk-speedup.pdf bulk-impact-speedup.pdf

matmul-runtimes-large.pdf: results/matmul-moderate.json results/matmul-incremental.json results/matmul-incremental-tuned.json results/matmul-reference.json tools/matmul-plot.py
	python tools/matmul-plot.py $@ $(MATMUL_SIZES_LARGE)

matmul-runtimes-small.pdf: results/matmul-moderate.json results/matmul-incremental.json results/matmul-incremental-tuned.json results/matmul-reference.json tools/matmul-plot.py
	python tools/matmul-plot.py $@ $(MATMUL_SIZES_SMALL)

# You will also have to modify the data set stanzas in
# benchmarks/matmul.fut if you change these.
MATMUL_SIZES_LARGE=0 10 25
MATMUL_SIZES_SMALL=0 10 20

benchmarks/matmul-data:
	mkdir -p $@
	tools/make_matmul_matrices.sh $(MATMUL_SIZES_LARGE)
	tools/make_matmul_matrices.sh $(MATMUL_SIZES_SMALL)

results/matmul-moderate.json: benchmarks/matmul-data $(FUTHARK_OPENCL_DEPS)
	mkdir -p results
	futhark-bench $(FUTHARK_BENCH_OPENCL_OPTIONS) benchmarks/matmul.fut --json $@
results/matmul-incremental.json: benchmarks/matmul-data $(FUTHARK_OPENCL_DEPS)
	mkdir -p results
	FUTHARK_INCREMENTAL_FLATTENING=1 futhark-bench $(FUTHARK_BENCH_OPENCL_OPTIONS) benchmarks/matmul.fut --json $@
results/matmul-incremental-tuned.json: benchmarks/matmul-data futhark $(FUTHARK_OPENCL_DEPS)
	mkdir -p results tunings
	FUTHARK_INCREMENTAL_FLATTENING=1 $(FUTHARK_AUTOTUNE) benchmarks/matmul.fut --save-json tunings/matmul.json
	FUTHARK_INCREMENTAL_FLATTENING=1 futhark-bench $(FUTHARK_BENCH_OPENCL_OPTIONS) benchmarks/matmul.fut --json $@ $$(python tools/tuning_json_to_options.py < tunings/matmul.json)
results/matmul-reference.json: reference/matmul/matmul
	mkdir -p results
	(cd reference/matmul; ./matmul ../../$@ $(MATMUL_SIZES_LARGE) $(MATMUL_SIZES_SMALL)) || rm $@

reference/matmul/matmul: reference/matmul/matmul.c
	$(CC) $< -o $@ $(CFLAGS)

fft-runtimes.pdf: results/fft-c.json results/fft-moderate.json results/fft-incremental.json results/fft-incremental-tuned.json tools/fft-plot.py
	python tools/fft-plot.py

benchmarks/fft-data: $(FUTHARK_C_DEPS)
	mkdir -p $@
	$(FUTHARK_C) benchmarks/fft.fut
	tools/make_fft_matrices.sh 2 10 24

results/fft-moderate.json: benchmarks/fft-data $(FUTHARK_OPENCL_DEPS)
	mkdir -p results
	futhark-bench $(FUTHARK_BENCH_OPENCL_OPTIONS) benchmarks/fft.fut --json $@
results/fft-incremental.json: benchmarks/fft-data $(FUTHARK_OPENCL_DEPS)
	mkdir -p results
	FUTHARK_INCREMENTAL_FLATTENING=1 futhark-bench $(FUTHARK_BENCH_OPENCL_OPTIONS) benchmarks/fft.fut --json $@
results/fft-incremental-tuned.json: benchmarks/fft-data futhark $(FUTHARK_OPENCL_DEPS)
	mkdir -p results tunings
	FUTHARK_INCREMENTAL_FLATTENING=1 $(FUTHARK_AUTOTUNE) benchmarks/fft.fut $(FUTHARK_BENCH_OPENCL_OPTIONS) --save-json tunings/fft.json
	FUTHARK_INCREMENTAL_FLATTENING=1 futhark-bench $(FUTHARK_BENCH_OPENCL_OPTIONS) benchmarks/fft.fut --json $@ $$(python tools/tuning_json_to_options.py < tunings/fft.json)

LocVolCalib-runtimes.pdf: results/LocVolCalib-partridag-moderate.json results/LocVolCalib-partridag-incremental.json results/LocVolCalib-moderate.json results/LocVolCalib-incremental.json results/LocVolCalib-partridag-incremental-tuned.json results/LocVolCalib-finpar-AllParOpenCLMP.json results/LocVolCalib-finpar-OutParOpenCLMP.json tools/LocVolCalib-plot.py
	python tools/LocVolCalib-plot.py

results/LocVolCalib-partridag-moderate.json: $(FUTHARK_OPENCL_DEPS)
	mkdir -p results
	futhark-bench $(FUTHARK_BENCH_OPENCL_OPTIONS) benchmarks/LocVolCalib-partridag.fut --json $@
results/LocVolCalib-partridag-incremental.json: $(FUTHARK_OPENCL_DEPS)
	mkdir -p results
	FUTHARK_INCREMENTAL_FLATTENING=1 futhark-bench $(FUTHARK_BENCH_OPENCL_OPTIONS) benchmarks/LocVolCalib-partridag.fut --json $@
results/LocVolCalib-moderate.json: $(FUTHARK_OPENCL_DEPS)
	mkdir -p results
	futhark-bench $(FUTHARK_BENCH_OPENCL_OPTIONS) benchmarks/LocVolCalib.fut --json $@
results/LocVolCalib-incremental.json: $(FUTHARK_OPENCL_DEPS)
	mkdir -p results
	FUTHARK_INCREMENTAL_FLATTENING=1 futhark-bench $(FUTHARK_BENCH_OPENCL_OPTIONS) benchmarks/LocVolCalib.fut --json $@
results/LocVolCalib-partridag-incremental-tuned.json: futhark $(FUTHARK_OPENCL_DEPS)
	mkdir -p results tunings
	FUTHARK_INCREMENTAL_FLATTENING=1 $(FUTHARK_AUTOTUNE) benchmarks/LocVolCalib-partridag.fut --stop-after $(AUTOTUNE_SECONDS_LOCVOLCALIB) --save-json tunings/LocVolCalib-partridag.json
	FUTHARK_INCREMENTAL_FLATTENING=1 futhark-bench $(FUTHARK_BENCH_OPENCL_OPTIONS) benchmarks/LocVolCalib-partridag.fut --json $@ $$(python tools/tuning_json_to_options.py < tunings/LocVolCalib-partridag.json)

results/LocVolCalib-finpar-%.json: results/LocVolCalib-%-small.raw results/LocVolCalib-%-medium.raw results/LocVolCalib-%-large.raw tools/LocVolCalib-json.py
	python tools/LocVolCalib-json.py $* > $@

results/LocVolCalib-AllParOpenCLMP-%.raw: bin/gpuid tools/run-finpar-bench.sh
	tools/run-finpar-bench.sh LocVolCalib/AllParOpenCLMP $* > $@ || (rm $@ && exit 1)

results/LocVolCalib-OutParOpenCLMP-%.raw: bin/gpuid tools/run-finpar-bench.sh
	tools/run-finpar-bench.sh LocVolCalib/OutParOpenCLMP $* > $@ || (rm $@ && exit 1)

results/OptionPricing-finpar.json: results/OptionPricing-finpar-small.raw results/OptionPricing-finpar-medium.raw results/OptionPricing-finpar-large.raw tools/OptionPricing-json.py
	python tools/OptionPricing-json.py > $@

results/OptionPricing-finpar-%.raw: bin/gpuid tools/run-finpar-bench.sh
	tools/run-finpar-bench.sh OptionPricing/CppOpenCL $* > $@ || (rm $@ && exit 1)

## Tools.

bin/gpuid: tools/gpuid.c
	mkdir -p bin
	$(CC) -o $@ $< $(CFLAGS)

## Now for Rodinia scaffolding.  Crufty and hacky.

RODINIA_BENCHMARKS=backprop

RODINIA_URL=http://www.cs.virginia.edu/~kw5na/lava/Rodinia/Packages/Current/rodinia_3.1.tar.bz2

rodinia_3.1-patched: rodinia_3.1.tar.bz2
	@if ! md5sum --quiet -c rodinia_3.1.tar.bz2.md5; then \
          echo "Your rodinia_3.1.tar.bz2 has the wrong MD5-sum - delete it and try again."; exit 1; fi
	tar jxf rodinia_3.1.tar.bz2
	mv rodinia_3.1 rodinia_3.1-patched
	(cd $@; patch -p1 < ../rodinia_3.1-some-instrumentation.patch)

rodinia_3.1.tar.bz2:
	wget http://www.cs.virginia.edu/~kw5na/lava/Rodinia/Packages/Current/rodinia_3.1.tar.bz2

# This is a development rule that users should never use.
rodinia_3.1-some-instrumentation.patch:
	diff -pur rodinia_3.1 rodinia_3.1-patched > $@ || true

# Skip the first measurement; we treat it as a warmup run.
results/%-rodinia.runtimes: bin/gpuid rodinia_3.1-patched
	mkdir -p results
	tools/rodinia_run.sh opencl/$* $(RODINIA_RUNS)
	tail -n +2 rodinia_3.1-patched/opencl/$*/runtimes > $@

## Parboil stuff

pb2.5driver.tgz:
	wget http://www.phoronix-test-suite.com/benchmark-files/pb2.5driver.tgz

pb2.5benchmarks.tgz:
	wget http://www.phoronix-test-suite.com/benchmark-files/pb2.5benchmarks.tgz

pb2.5datasets_standard.tgz:
	wget http://www.phoronix-test-suite.com/benchmark-files/pb2.5datasets_standard.tgz

parboil-patched: pb2.5driver.tgz pb2.5benchmarks.tgz pb2.5datasets_standard.tgz
	tar -xf pb2.5driver.tgz
	mv parboil parboil-patched
	echo 'OPENCL_PATH=/' > parboil-patched/common/Makefile.conf
	tar -C parboil-patched -xf pb2.5benchmarks.tgz
	tar -C parboil-patched -xf pb2.5datasets_standard.tgz

# This is a development rule that users should never use.
parboil-fixes.patch:
	diff -pur parboil parboil-patched > $@ || true

results/mri-q-parboil.runtimes: bin/gpuid parboil-patched
	tools/parboil_run.sh mri-q opencl large 10 > $@

results/stencil-parboil.runtimes: bin/gpuid parboil-patched
	tools/parboil_run.sh stencil opencl_nvidia default 10 > $@

results/tpacf-parboil.runtimes: bin/gpuid parboil-patched
	tools/parboil_run.sh tpacf opencl_nvidia large 10 > $@

## Bulk benchmarking

results/bulk-reference.json: tools/bulk-json.py results/backprop-rodinia.runtimes results/hotspot-rodinia.runtimes results/cfd-rodinia.runtimes results/kmeans-rodinia.runtimes results/lavaMD-rodinia.runtimes results/nn-rodinia.runtimes results/pathfinder-rodinia.runtimes results/srad-rodinia.runtimes results/OptionPricing-finpar.json results/mri-q-parboil.runtimes results/stencil-parboil.runtimes results/tpacf-parboil.runtimes
	tools/bulk-json.py > $@

BULK_BENCHMARKS=rodinia/backprop/backprop.fut rodinia/hotspot/hotspot.fut rodinia/cfd/cfd.fut rodinia/kmeans/kmeans.fut rodinia/lavaMD/lavaMD.fut rodinia/nn/nn.fut rodinia/pathfinder/pathfinder.fut rodinia/srad/srad.fut parboil/mri-q/mri-q.fut parboil/stencil/stencil.fut parboil/tpacf/tpacf.fut finpar/OptionPricing.fut

results/bulk-moderate.json: futhark-benchmarks $(FUTHARK_OPENCL_DEPS)
	mkdir -p results
	futhark-bench $(FUTHARK_BENCH_OPENCL_OPTIONS) --json $@ $(BULK_BENCHMARKS:%.fut=futhark-benchmarks/%.fut)

results/bulk-incremental.json: futhark-benchmarks $(FUTHARK_OPENCL_DEPS)
	mkdir -p results
	FUTHARK_INCREMENTAL_FLATTENING=1 futhark-bench $(FUTHARK_BENCH_OPENCL_OPTIONS) --json $@ $(BULK_BENCHMARKS:%.fut=futhark-benchmarks/%.fut)

bulk-speedup.pdf: results/bulk-reference.json results/bulk-moderate.json results/bulk-incremental.json tools/bulk-plot.py
	tools/bulk-plot.py $@

## Bulk (impact) benchmarking

results/%-moderate.json: benchmarks/%-data futhark-benchmarks $(FUTHARK_OPENCL_DEPS)
	mkdir -p results
	futhark-bench $(FUTHARK_BENCH_OPENCL_OPTIONS) benchmarks/$*.fut --json $@

results/%-incremental.json: benchmarks/%-data futhark-benchmarks $(FUTHARK_OPENCL_DEPS)
	mkdir -p results
	FUTHARK_INCREMENTAL_FLATTENING=1 futhark-bench $(FUTHARK_BENCH_OPENCL_OPTIONS) benchmarks/$*.fut --json $@

tunings/%.json: benchmarks/%-data futhark futhark-benchmarks $(FUTHARK_OPENCL_DEPS)
	mkdir -p tunings
	FUTHARK_INCREMENTAL_FLATTENING=1 $(FUTHARK_AUTOTUNE) benchmarks/$*.fut --save-json tunings/$*.json

results/%-incremental-tuned.json: tunings/%.json futhark-benchmarks $(FUTHARK_OPENCL_DEPS)
	mkdir -p results
	FUTHARK_INCREMENTAL_FLATTENING=1 futhark-bench $(FUTHARK_BENCH_OPENCL_OPTIONS) benchmarks/$*.fut --json $@ $$(python tools/tuning_json_to_options.py < tunings/$*.json)

benchmarks/nn-data:
	mkdir -p $@
	N=256 M=2048 sh -c '(echo 100; futhark-dataset -b -g [$$N]f32 -g [$$N]f32 -g [$$N][$$M]f32 -g [$$N][$$M]f32) > $@/n$${N}_m$${M}'
	N=1024 M=512 sh -c '(echo 100; futhark-dataset -b -g [$$N]f32 -g [$$N]f32 -g [$$N][$$M]f32 -g [$$N][$$M]f32) > $@/n$${N}_m$${M}'
	N=4096 M=128 sh -c '(echo 100; futhark-dataset -b -g [$$N]f32 -g [$$N]f32 -g [$$N][$$M]f32 -g [$$N][$$M]f32) > $@/n$${N}_m$${M}'

bulk-impact-speedup.pdf: results/nn-moderate.json results/nn-incremental.json results/nn-incremental-tuned.json results/OptionPricing-moderate.json results/OptionPricing-incremental.json results/OptionPricing-incremental-tuned.json tools/bulk-impact-plot.py
	tools/bulk-impact-plot.py $@

#n# Initialising the submodules

futhark:
	git submodule init
	git submodule update

futhark-benchmarks:
	git submodule init
	git submodule update

finpar:
	git submodule init
	git submodule update

## Building Futhark

bin/futhark-%: futhark
	mkdir -p bin
	cd futhark && stack setup
	cd futhark && stack build
	cp `cd futhark && stack exec which futhark-$*` $@

clean:
	rm -rf bin benchmarks/*.expected benchmarks/*.actual benchmarks/*-c benchmarks/matmul-data benchmarks/fft-data benchmarks/nn-data tunings results *.pdf finpar.log

veryclean: clean
	rm -rf  rodinia_3.1-patched *.tgz *.tar.gz futhark finpar futhark-benchmarks
