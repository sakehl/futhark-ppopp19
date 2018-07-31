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

ifeq ($(FUTHARK_DATASET),bin/futhark-dataset)
  FUTHARK_DATASET_DEPS=bin/futhark-dataset
endif


FUTHARK_AUTOTUNE=futhark/tools/futhark-autotune $(FUTHARK_BENCH_OPENCL_OPTIONS) --stop-after $(AUTOTUNE_SECONDS)

.PHONY: all clean veryclean
.SUFFIXES:
.SECONDARY:

all: $(FUTHARK_OPENCL_DEPS) rodinia_3.1-patched parboil-patched plots

plots: matmul-runtimes-large.pdf matmul-runtimes-small.pdf LocVolCalib-runtimes.pdf bulk-speedup.pdf bulk-impact-speedup.pdf

matmul-runtimes-large.pdf: results/matmul-moderate.json results/matmul-incremental.json results/matmul-incremental-tuned.json results/matmul-reference.json tools/matmul-plot.py
	python tools/matmul-plot.py $@ $(MATMUL_SIZES_LARGE)

matmul-runtimes-small.pdf: results/matmul-moderate.json results/matmul-incremental.json results/matmul-incremental-tuned.json results/matmul-reference.json tools/matmul-plot.py
	python tools/matmul-plot.py $@ $(MATMUL_SIZES_SMALL)


# General rules for running the simple cases of benchmarks.
results/%-moderate.json: benchmarks/%.fut benchmarks/%-data $(FUTHARK_OPENCL_DEPS)
	mkdir -p results
	futhark-bench $(FUTHARK_BENCH_OPENCL_OPTIONS) benchmarks/$*.fut --json $@
results/%-incremental.json: benchmarks/%.fut benchmarks/%-data $(FUTHARK_OPENCL_DEPS)
	mkdir -p results
	FUTHARK_INCREMENTAL_FLATTENING=1 futhark-bench $(FUTHARK_BENCH_OPENCL_OPTIONS) benchmarks/$*.fut --json $@
results/%-incremental-tuned.json: benchmarks/%.fut benchmarks/%-data futhark $(FUTHARK_OPENCL_DEPS)
	mkdir -p results tunings
	FUTHARK_INCREMENTAL_FLATTENING=1 $(FUTHARK_AUTOTUNE) benchmarks/$*.fut $(FUTHARK_BENCH_OPENCL_OPTIONS) --save-json tunings/$*.json
	FUTHARK_INCREMENTAL_FLATTENING=1 futhark-bench $(FUTHARK_BENCH_OPENCL_OPTIONS) benchmarks/$*.fut --json $@ $$(python tools/tuning_json_to_options.py < tunings/$*.json)

# You will also have to modify the data set stanzas in
# benchmarks/matmul.fut if you change these.
MATMUL_SIZES_LARGE=0 10 25
MATMUL_SIZES_SMALL=0 10 20

benchmarks/matmul-data:
	mkdir -p $@
	tools/make_matmul_matrices.sh $(MATMUL_SIZES_LARGE)
	tools/make_matmul_matrices.sh $(MATMUL_SIZES_SMALL)

reference/matmul/matmul: reference/matmul/matmul.c
	$(CC) $< -o $@ $(CFLAGS)

benchmarks/pathfinder-data: $(FUTHARK_C_DEPS) $(FUTHARK_DATASET_DEPS)
	mkdir -p $@
	$(FUTHARK_DATASET) -b -g [391][100][256]i32 > $@/391_100_256.in
	$(FUTHARK_C) benchmarks/pathfinder.fut
	benchmarks/pathfinder -b < $@/391_100_256.in > $@/391_100_256.out

LocVolCalib-runtimes.pdf: results/LocVolCalib-moderate.json results/LocVolCalib-incremental.json results/LocVolCalib-finpar-AllParOpenCLMP.json results/LocVolCalib-finpar-OutParOpenCLMP.json tools/LocVolCalib-plot.py
	python tools/LocVolCalib-plot.py

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
	patch -p0 < parboil-fixes.patch

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

benchmarks/nn-data: $(FUTHARK_DATASET_DEPS)
	mkdir -p $@
	N=256 M=2048 sh -c '(echo 100; $(FUTHARK_DATASET) -b -g [$$N]f32 -g [$$N]f32 -g [$$N][$$M]f32 -g [$$N][$$M]f32) > $@/n$${N}_m$${M}'
	N=1024 M=512 sh -c '(echo 100; $(FUTHARK_DATASET) -b -g [$$N]f32 -g [$$N]f32 -g [$$N][$$M]f32 -g [$$N][$$M]f32) > $@/n$${N}_m$${M}'
	N=4096 M=128 sh -c '(echo 100; $(FUTHARK_DATASET) -b -g [$$N]f32 -g [$$N]f32 -g [$$N][$$M]f32 -g [$$N][$$M]f32) > $@/n$${N}_m$${M}'

bulk-impact-speedup.pdf: results/nn-moderate.json results/nn-incremental.json results/nn-incremental-tuned.json results/OptionPricing-moderate.json results/OptionPricing-incremental.json results/OptionPricing-incremental-tuned.json tools/bulk-impact-plot.py
	tools/bulk-impact-plot.py $@

## Building Futhark

bin/futhark-%:
	mkdir -p bin
	cd futhark && stack setup
	cd futhark && stack build
	cp `cd futhark && stack exec which futhark-$*` $@

bin/futhark:
	mkdir -p bin
	cd futhark && stack setup
	cd futhark && stack build
	cp `cd futhark && stack exec which futhark` $@

clean:
	rm -rf bin benchmarks/*.expected benchmarks/*.actual benchmarks/*-c benchmarks/matmul-data benchmarks/pathfinder-data benchmarks/nn-data tunings results *.pdf finpar.log

veryclean: clean
	rm -rf  rodinia_3.1-patched *.tgz *.tar.gz futhark finpar futhark-benchmarks
