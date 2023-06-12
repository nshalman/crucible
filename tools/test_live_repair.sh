#!/bin/bash

# Create and start up the downstairs.
# In a loop:
#  Send IO through crutest
#  Fault a downstairs
#  Let the upstairs repair.

err=0
total=0
pass_total=0
SECONDS=0
dropshot=0
ulimit -n 65536

# Control-C to cleanup.
trap ctrl_c INT
function ctrl_c() {
    echo "Stopping at your request"
    if ps -p "$dsc_pid" ; then
        ${dsc} cmd shutdown
        wait "$dsc_pid"
    fi
    if ps -p "$crutest_pid" ; then
        kill "$crutest_pid"
        wait "$crutest_pid"
    fi
}

loop_log=/tmp/test_live_repair_summary.log
test_log=/tmp/test_live_repair.log
dsc_test_log=/tmp/test_live_repair_dsc.log
verify_file=/tmp/test_live_verify

ROOT=$(cd "$(dirname "$0")/.." && pwd)
export BINDIR=${BINDIR:-$ROOT/target/release}
cds="$BINDIR/crucible-downstairs"
crucible_test="$BINDIR/crutest"
dsc="$BINDIR/dsc"
for bin in $cds $crucible_test $dsc; do
    if [[ ! -f "$bin" ]]; then
        echo "Can't find crucible binary at $bin" >&2
        exit 1
    fi
done

# Verify there is not a downstairs already running.
if pgrep -fl -U "$(id -u)" "$cds"; then
    echo "Downstairs already running" >&2
    echo Run: pkill -f -U "$(id -u)" "$cds" >&2
    exit 1
fi

echo "" > ${loop_log}
echo "" > ${test_log}
echo "" > ${dsc_test_log}
if [[ -f "$verify_file" ]]; then
    rm  ${verify_file}
fi
echo "starting $(date)" | tee ${loop_log}
echo "Tail $test_log for test output"

# Large extents, but not many of them means we are likely to try to write
# to an extent that is being repaired.
if ! ${dsc} create --cleanup \
  --ds-bin "$cds" \
  --extent-count 100 \
  --extent-size 300 >> "$dsc_test_log"; then
    echo "Failed to create downstairs regions"
    exit 1
fi
${dsc} start --ds-bin "$cds" >> "$dsc_test_log" 2>&1 &
dsc_pid=$!
sleep 5
if ! ps -p $dsc_pid > /dev/null; then
    echo "$dsc failed to start"
    exit 1
fi

args=()
port_base=8810
for (( i = 0; i < 30; i += 10 )); do
    (( port = port_base + i ))
    args+=( -t "127.0.0.1:$port" )
done

gen=1
# Initial seed for verify file
if ! "$crucible_test" fill "${args[@]}" -q -g "$gen"\
          --verify-out "$verify_file" \
          --retry-activate >> "$test_log" 2>&1 ; then
    echo Failed on initial verify seed, check "$test_log"
    ${dsc} cmd shutdown
fi
(( gen += 1 ))

for i in {1..20}
do
    SECONDS=0
    choice=$((RANDOM % 3))
    echo "" > "$test_log"
    echo "New loop starts now $(date) faulting: $choice" >> "$test_log"
    # This has to be long enough that faulting a downstairs will be
    # noticed, but not so long that the test takes forever.
    "$crucible_test" generic "${args[@]}" --continuous \
        -q -g "$gen" --verify-out "$verify_file" \
        --verify-in "$verify_file" \
        --control 127.0.0.1:7777 \
        --retry-activate >> "$test_log" 2>&1 &
    crutest_pid=$!
    sleep 5

    # Fault a downstairs.
    curl -s -X POST http://127.0.0.1:7777/downstairs/fault/"${choice}"

    # Give the fault time to be noticed
    sleep 5


	# Now wait for all downstairs to be active
    all_state=$(curl -s http://127.0.0.1:7777/info | awk -F\" '{print $8","$10","$12}')
    while [[ "${all_state}" != "active,active,active" ]]; do
        sleep 5
        all_state=$(curl -s http://127.0.0.1:7777/info | awk -F\" '{print $8","$10","$12}')
    done

	# All downstairs now active, stop crutest.
    kill -SIGUSR1 $crutest_pid
    wait ${crutest_pid}
    result=$?
    if [[ $result -ne 0 ]]; then
        if tail "$test_log" | grep dropshot > /dev/null ; then
            (( dropshot += 1 ))
        else
            (( err += 1 ))
            duration=$SECONDS
            printf "[%03d] Error $result after %d:%02d\n" "$i" \
                    $((duration / 60)) $((duration % 60)) | tee -a ${loop_log}
            mv "$test_log" "$test_log".lastfail
            break
        fi
    fi

    (( gen += 1 ))
    # Run a verify now
    if ! "$crucible_test" verify "${args[@]}" -q -g "$gen" \
      --verify-in "$verify_file" \
      --control 127.0.0.1:7777 >> "$test_log" 2>&1 ; then
        if tail "$test_log" | grep dropshot > /dev/null ; then
            (( dropshot += 1 ))
        else
            mv "$test_log" "$test_log".lastfail
            echo "verify failed on loop $i"
            (( err += 1 ))
            break
        fi
    fi

    duration=$SECONDS
    (( gen += 1 ))
    (( pass_total += 1 ))
    (( total += duration ))
    ave=$(( total / pass_total ))
    printf \
      "[%03d][%d] %d:%02d  ds_err:%d ave:%d:%02d total:%d:%02d last_run:%d\n" \
      "$i" "$choice" \
      $((duration / 60)) $((duration % 60)) \
      "$dropshot"  \
      $((ave / 60)) $((ave % 60))  $((total / 60)) $((total % 60)) \
      "$duration" | tee -a ${loop_log}

done

# Stop dsc.
${dsc} cmd shutdown
wait ${dsc_pid}

echo "Final results:" | tee -a ${loop_log}
printf \
  "[%03d] %d:%02d  ave:%d:%02d  total:%d:%02d errors:%d last_run_seconds:%d\n" \
  "$i" $((duration / 60)) $((duration % 60)) \
  $((ave / 60)) $((ave % 60)) $((total / 60)) $((total % 60)) \
  "$err" $duration | tee -a ${loop_log}
echo "$(date) Test ends with $err" >> "$test_log"
exit "$err"
