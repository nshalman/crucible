#!/bin/bash

# A stress test of replacing a downstairs while reconciliation is underway.
# Using dsc, we create the regions and start up four downstairs.
# Run the crutest special replacement tests using the downstairs we just
# started, with the fourth being the first one to replace.
err=0
total=0
pass_total=0
SECONDS=0

# Control-C to cleanup.
trap ctrl_c INT
function ctrl_c() {
    echo "Stopping at your request"
    ${dsc} cmd shutdown
    exit 1
}

REGION_ROOT=${REGION_ROOT:-/var/tmp/test_replace_special}
mkdir -p "$REGION_ROOT"

# Location of logs and working files
WORK_ROOT=${WORK_ROOT:-/tmp}
mkdir -p "$WORK_ROOT"

loop_log="$WORK_ROOT"/test_replace_special_summary.log
test_log="$WORK_ROOT"/test_replace_special.log
verify_log="$WORK_ROOT/test_replace_special_verify.log"


ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || (echo failed to cd "$ROOT"; exit 1)
export BINDIR=${BINDIR:-$ROOT/target/debug}
crucible_test="$BINDIR/crutest"
dsc="$BINDIR/dsc"
downstairs="$BINDIR/crucible-downstairs"
if [[ ! -f "$crucible_test" ]] || [[ ! -f "$dsc" ]] || [[ ! -f "$downstairs" ]]; then
    echo "Can't find required binaries"
    echo "Missing $crucible_test or $dsc or $downstairs"
    exit 1
fi

loops=5
region_sets=1

usage () {
    echo "Usage: $0 [-l #] [-r #]" >&2
    echo " -l loops       Number of test loops to perform (default 5)" >&2
    echo " -r region_sets Number of region sets to create (default 1)" >&2
}

while getopts 'l:r:' opt; do
    case "$opt" in
        l)  loops=$OPTARG
            ;;
        r) region_sets=$OPTARG
            ;;
        *)  echo "Invalid option"
            usage
            exit 1
            ;;
    esac
done

((region_count=region_sets*3))
((region_count+=1))
echo "" > "$loop_log"
echo "" > "$test_log"
echo "starting $(date)" | tee "$loop_log"
echo "Tail $test_log for test output"

# NOTE: We creating the requested number of regions here plus one more region
# to be used for replacement.  We can use dsc to determine what the port will
# be for the final region
if ! ${dsc} create --cleanup \
  --region-dir "$REGION_ROOT" \
  --region-count "$region_count" \
  --ds-bin "$downstairs" \
  --extent-count 400 \
  --block-size 4096 >> "$test_log"; then
    echo "Failed to create downstairs regions"
    exit 1
fi
${dsc} start --ds-bin "$downstairs" \
  --region-dir "$REGION_ROOT" \
  --region-count "$region_count" >> "$test_log" 2>&1 &
dsc_pid=$!
sleep 5
if ! ps -p $dsc_pid > /dev/null; then
    echo "$dsc failed to start"
    exit 1
fi

gen=1
# Initial seed for verify file
if ! "$crucible_test" fill --dsc 127.0.0.1:9998 -q -g "$gen"\
  --skip-verify >> "$test_log" 2>&1 ; then
    echo Failed on initial fill, check "$test_log"
    ${dsc} cmd shutdown
    exit 1
fi
(( gen += 1 ))

# Figure out the port of the last dsc client, this is what we will use for the
# replacement address.
((last_client=region_count - 1))
replacement_port=$(${dsc} cmd port -c $last_client)

# Now run the crutest replace-reconcile test
SECONDS=0
cp "$test_log" "$test_log".last
echo "" > "$test_log"
echo "$(date) replace-reconcile starts now" | tee -a "$test_log"
"$crucible_test" replace-reconcile -c "$loops" --dsc 127.0.0.1:9998 \
  --replacement 127.0.0.1:"$replacement_port" \
  --stable -g "$gen" >> "$test_log" 2>&1
result=$?
duration=$SECONDS
if [[ $result -ne 0 ]]; then
    printf "Error $result after %d:%02d\n" \
      $((duration / 60)) $((duration % 60)) | tee -a "$loop_log"
    cp "$test_log" "$test_log".lastfail
else
    printf "Test took %d:%02d\n" \
      $((duration / 60)) $((duration % 60)) | tee -a "$loop_log"
fi

${dsc} cmd shutdown
wait "$dsc_pid"

echo "$(date) Test ends with $result" | tee -a "$test_log"
exit $result
