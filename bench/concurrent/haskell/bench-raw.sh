#!/bin/bash

info() {
    echo -e "\e[34m$1\e[0m" >&2
}

sep() {
    echo "" >&2
}

addfield() {
    sed $'s/$/\t'"$1/"
}

runbasic() {
    local desc="$1"
    shift

    #echo taskset -c 0-5 parbench "$@"
    parbench "$@" | addfield "$desc"
}

run() {
    local desc="$1"
    shift
    local par="$1"
    shift

    runbasic "$desc" --n=$par +RTS -qa -N$par -RTS "$@"
}


info_system() {
    info "> $system"
    case $system in
        fscq)
            is_fscq=true ;;
        cfscq)
            is_fscq=false ;;
        *)
            echo "invalid system $system" >&2
            exit 1
    esac
}

parse_disk() {
    case $disk in
        mem)
            img="/tmp/disk.img" ;;
        ssd)
            img="/dev/sdg1" ;;
        hdd)
            img="/dev/sda4" ;;
        *)
            echo "invalid disk $disk" >&2
            exit 1
    esac
}

# benchmarks

syscalls() {
	info "syscall baseline"
	for system in fscq cfscq; do
		info_system
		for par in $(seq 1 12); do
			info "  > n=$par"
			args=( $par "--img=/tmp/disk.img" "--target-ms=500" "--fscq=$is_fscq" )
			run ""            "${args[@]}" statfs --reps=1000
			run ""            "${args[@]}" stat   --reps=10
			run ""            "${args[@]}" open   --reps=10
			run "oob"         "${args[@]}" read   --reps=10 --file="/small" --offset 10000
			run "off-0"       "${args[@]}" read   --reps=10 --file="/small" --offset 0
			run "large"       "${args[@]}" cat-file     --file="/large"
			run "large-dir"   "${args[@]}" traverse-dir --dir="/large-dir"
			run "small files" "${args[@]}" cat-dir      --dir="/large-dir-small-files"
			run ""            "${args[@]}" create
			run ""            "${args[@]}" create-dir
			run ""            "${args[@]}" write
		done
	done
	sep
}

io_concur() {
	info "I/O concurrency"
	for system in fscq cfscq; do
		info_system
		for par in 1 2; do
			for capabilities in 1 2; do
				for disk in "mem" "ssd" "hdd"; do
					parse_disk
					runbasic "$disk" +RTS -qa -N$capabilities -RTS \
						--n=$par --fscq=$is_fscq --img=$img \
						io-concur --reps=25000
				done
			done
		done
	done
	sep
}


dbench() {
	info "dbench"
	for system in fscq cfscq; do
		info_system
		for disk in "mem" "ssd"; do
			parse_disk
			run "$disk" 1 --img="$img" --fscq=$is_fscq \
				dbench --script $HOME/dbench/loadfiles/client.txt
		done
	done
	sep
}

parsearch() {
	info "par-search"
	for system in fscq cfscq; do
		info_system
		for par in $(seq 1 12); do
			info "  > n=$par"
			run "warmup" $par --img=/tmp/disk.img --fscq=$is_fscq \
				par-search --dir '/search-benchmarks/coq' --query 'dependency graph'
			run "mem" $par --img=/tmp/disk.img --fscq=$is_fscq --warmup=false \
				par-search --dir '/search-benchmarks/coq' --query 'dependency graph'
		done
	done
	sep
}

readers_writer() {
	info "readers-writer"
	for par in $(seq 0 11); do
		info "> n=$par"
		args=( --n=$par +RTS -qa -N$((par+1)) -RTS --img=/tmp/disk.img --fscq=false --iters=5000 )
		runbasic "" "${args[@]}" readers-writer --reps=10 --write-reps=1
		if [ $par -eq 1 ]; then
			runbasic "only-reads" "${args[@]}" \
				+RTS -N1 -RTS \
				readers-writer --reps=10 --write-reps=1 --only-reads
		fi
	done
	sep
}

rw_mix() {
	info "rw-mix"
	for par in $(seq 1 12); do
		info "> n=$par"
		args=( --n=$par +RTS -qa -N$par -RTS --img=/tmp/disk.img --fscq=false --target-ms=1000 )
		for mix in 0.95 0.9 0.8; do
			runbasic "mix-$mix" "${args[@]}" \
				rw-mix --reps=10 --write-reps=1 --read-perc=$mix
		done
	done
}

parbench print-header | addfield "description"

syscalls
io_concur
dbench
parsearch
readers_writer
rw_mix