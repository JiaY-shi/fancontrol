#!/bin/sh

set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BINARY="$PROJECT_DIR/fancontrol/src/fancontrol"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fancontrol-test.XXXXXX")
SYSFS_ROOT="$TEST_ROOT/sys"
STATUS_FILE="$TEST_ROOT/fancontrol.status"
PWM_FILE="$SYSFS_ROOT/class/hwmon/hwmon7/pwm1"
ENABLE_FILE="$SYSFS_ROOT/class/hwmon/hwmon7/pwm1_enable"
TEMP_FILE="$SYSFS_ROOT/class/thermal/thermal_zone0/temp"
DAEMON_PID=""
KERNEL_PID=""

cleanup() {
	if [ -n "$DAEMON_PID" ]; then
		kill "$DAEMON_PID" 2>/dev/null || true
		wait "$DAEMON_PID" 2>/dev/null || true
	fi
	if [ -n "$KERNEL_PID" ]; then
		kill "$KERNEL_PID" 2>/dev/null || true
		wait "$KERNEL_PID" 2>/dev/null || true
	fi
	rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT HUP INT TERM

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

assert_file_value() {
	file="$1"
	expected="$2"
	actual=$(tr -d '\r\n' < "$file")
	[ "$actual" = "$expected" ] ||
		fail "$file: expected $expected, got $actual"
}

run_once() {
	temperature="$1"
	expected="$2"
	printf '%s\n' "$temperature" > "$TEMP_FILE"
	printf '%s\n' 17 > "$PWM_FILE"
	printf '%s\n' 2 > "$ENABLE_FILE"
	FANCONTROL_SYSFS_ROOT="$SYSFS_ROOT" \
	FANCONTROL_STATUS_FILE="$STATUS_FILE" \
		"$BINARY" -1 -k 0 -K 0
	assert_file_value "$PWM_FILE" "$expected"
	assert_file_value "$ENABLE_FILE" 1
}

wait_for_value() {
	file="$1"
	expected="$2"
	attempt=0
	while [ "$attempt" -lt 30 ]; do
		[ -r "$file" ] && [ "$(tr -d '\r\n' < "$file")" = "$expected" ] && return 0
		attempt=$((attempt + 1))
		sleep 0.1
	done
	fail "$file did not become $expected"
}

[ -x "$BINARY" ] || fail "build fancontrol before running this test"

mkdir -p "$SYSFS_ROOT/class/thermal/thermal_zone0"
mkdir -p "$SYSFS_ROOT/class/hwmon/hwmon0"
mkdir -p "$SYSFS_ROOT/class/hwmon/hwmon7"
printf '%s\n' cpu-thermal > "$SYSFS_ROOT/class/thermal/thermal_zone0/type"
printf '%s\n' generic-controller > "$SYSFS_ROOT/class/hwmon/hwmon0/name"
printf '%s\n' 99 > "$SYSFS_ROOT/class/hwmon/hwmon0/pwm1"
printf '%s\n' pwmfan > "$SYSFS_ROOT/class/hwmon/hwmon7/name"
printf '%s\n' 0 > "$SYSFS_ROOT/class/hwmon/hwmon7/fan1_input"

run_once 44000 0
run_once 45000 64
run_once 65000 159
run_once 85000 255
assert_file_value "$SYSFS_ROOT/class/hwmon/hwmon0/pwm1" 99

printf '%s\n' invalid > "$TEMP_FILE"
printf '%s\n' 0 > "$PWM_FILE"
FANCONTROL_SYSFS_ROOT="$SYSFS_ROOT" \
FANCONTROL_STATUS_FILE="$STATUS_FILE" \
	"$BINARY" -1 -k 0 -K 0
assert_file_value "$PWM_FILE" 255

printf '%s\n' 45000 > "$TEMP_FILE"
printf '%s\n' 0 > "$PWM_FILE"
FANCONTROL_SYSFS_ROOT="$SYSFS_ROOT" \
FANCONTROL_STATUS_FILE="$STATUS_FILE" \
	"$BINARY" -k 0 -K 0 -i 1 -q 0 &
DAEMON_PID=$!
wait_for_value "$PWM_FILE" 64
printf '%s\n' 44000 > "$TEMP_FILE"
sleep 2
assert_file_value "$PWM_FILE" 64
printf '%s\n' 42000 > "$TEMP_FILE"
wait_for_value "$PWM_FILE" 0
kill "$DAEMON_PID"
wait "$DAEMON_PID"
DAEMON_PID=""

# Systems without thermal zones may expose temperatures through hwmon only.
rm -rf -- "$SYSFS_ROOT/class/thermal"
printf '%s\n' cpu_sensor > "$SYSFS_ROOT/class/hwmon/hwmon0/name"
printf '%s\n' 45000 > "$SYSFS_ROOT/class/hwmon/hwmon0/temp1_input"
printf '%s\n' 0 > "$PWM_FILE"
FANCONTROL_SYSFS_ROOT="$SYSFS_ROOT" \
FANCONTROL_STATUS_FILE="$STATUS_FILE" \
	"$BINARY" -1 -k 0 -K 0
assert_file_value "$PWM_FILE" 64

# A thermal cooling state is an index, so accepting it would lose PWM resolution.
mkdir -p "$SYSFS_ROOT/class/thermal/cooling_device0"
printf '%s\n' 0 > "$SYSFS_ROOT/class/thermal/cooling_device0/cur_state"
if FANCONTROL_SYSFS_ROOT="$SYSFS_ROOT" \
	FANCONTROL_STATUS_FILE="$STATUS_FILE" \
	"$BINARY" -1 -T "$SYSFS_ROOT/class/hwmon/hwmon0/temp1_input" \
	-F "$SYSFS_ROOT/class/thermal/cooling_device0/cur_state"; then
	fail "cooling_device cur_state was accepted as a PWM output"
fi

# The kernel may control a fan from a different zone than the selected sensor.
# Simulate its independent PWM writer and real cdev symlinks, not a second daemon.
ZONE="$SYSFS_ROOT/class/thermal/thermal_zone1"
CDEV="$SYSFS_ROOT/class/thermal/cooling_device0"
mkdir -p "$SYSFS_ROOT/class/thermal/thermal_zone0" "$ZONE" "$CDEV"
mkdir -p "$SYSFS_ROOT/class/thermal/cooling_device1"
printf '%s\n' cpu-thermal > "$SYSFS_ROOT/class/thermal/thermal_zone0/type"
printf '%s\n' 48000 > "$TEMP_FILE"
printf '%s\n' pwm-fan > "$CDEV/type"
printf '%s\n' Processor > "$SYSFS_ROOT/class/thermal/cooling_device1/type"
printf '%s\n' enclosure-thermal > "$ZONE/type"
printf '%s\n' step_wise > "$ZONE/policy"
printf '%s\n' enabled > "$ZONE/mode"
printf '%s\n' critical > "$ZONE/trip_point_0_type"
printf '%s\n' 115000 > "$ZONE/trip_point_0_temp"
printf '%s\n' passive > "$ZONE/trip_point_1_type"
printf '%s\n' 105000 > "$ZONE/trip_point_1_temp"
for entry in '0 2 100000' '1 3 75000' '2 4 50000'; do
	set -- $entry
	ln -s ../cooling_device0 "$ZONE/cdev$1"
	printf '%s\n' "$2" > "$ZONE/cdev${1}_trip_point"
	printf '%s\n' active > "$ZONE/trip_point_${2}_type"
	printf '%s\n' "$3" > "$ZONE/trip_point_${2}_temp"
done
ln -s ../cooling_device1 "$ZONE/cdev3"
printf '%s\n' 1 > "$ZONE/cdev3_trip_point"

(
	while :; do
		if [ "$(cat "$ZONE/trip_point_4_temp")" != -274000 ]; then
			printf '%s\n' 36 > "$PWM_FILE"
		fi
		sleep 0.1
	done
) &
KERNEL_PID=$!

start_thermal_daemon() {
	FANCONTROL_SYSFS_ROOT="$SYSFS_ROOT" \
	FANCONTROL_STATUS_FILE="$STATUS_FILE" \
		"$BINARY" -t 70 -x 95 -k 0 -K 0 -i 1 &
	DAEMON_PID=$!
	wait_for_value "$ZONE/trip_point_4_temp" -274000
	wait_for_value "$PWM_FILE" 0
}

start_thermal_daemon
assert_file_value "$ZONE/trip_point_2_temp" -274000
assert_file_value "$ZONE/trip_point_3_temp" -274000
assert_file_value "$ZONE/trip_point_0_temp" 115000
assert_file_value "$ZONE/trip_point_1_temp" 105000
assert_file_value "$ZONE/policy" step_wise
assert_file_value "$ZONE/mode" enabled
sleep 2
assert_file_value "$PWM_FILE" 0
printf '%s\n' 80000 > "$TEMP_FILE"
wait_for_value "$PWM_FILE" 140
sleep 2
assert_file_value "$PWM_FILE" 140

# A second instance must not restore trips or delete the running daemon's status.
if FANCONTROL_SYSFS_ROOT="$SYSFS_ROOT" FANCONTROL_STATUS_FILE="$STATUS_FILE" \
	"$BINARY" -1 -k 0 -K 0; then
	fail "second controller instance was allowed"
fi
[ -f "$STATUS_FILE" ] || fail "second instance removed controller status"
assert_file_value "$ZONE/trip_point_4_temp" -274000

# SIGKILL cannot run cleanup. The next process must recover the original values
# before claiming the fan again, so a later graceful stop restores the real trips.
kill -KILL "$DAEMON_PID"
wait "$DAEMON_PID" 2>/dev/null || true
DAEMON_PID=""
[ -f "$STATUS_FILE.thermal" ] || fail "original trips were not journaled"
printf '%s\n' 48000 > "$TEMP_FILE"
start_thermal_daemon
kill "$DAEMON_PID"
wait "$DAEMON_PID"
DAEMON_PID=""
assert_file_value "$ZONE/trip_point_2_temp" 100000
assert_file_value "$ZONE/trip_point_3_temp" 75000
assert_file_value "$ZONE/trip_point_4_temp" 50000
[ ! -e "$STATUS_FILE.thermal" ] || fail "restored thermal journal remains"
wait_for_value "$PWM_FILE" 36
kill "$KERNEL_PID"
wait "$KERNEL_PID" 2>/dev/null || true
KERNEL_PID=""

# A fan trip shared with CPU cooling must be rejected without changing any trips.
printf '%s\n' 4 > "$ZONE/cdev3_trip_point"
printf '%s\n' 99 > "$PWM_FILE"
if FANCONTROL_SYSFS_ROOT="$SYSFS_ROOT" FANCONTROL_STATUS_FILE="$STATUS_FILE" \
	"$BINARY" -1 -k 0 -K 0; then
	fail "shared fan/CPU trip was disabled"
fi
assert_file_value "$ZONE/trip_point_2_temp" 100000
assert_file_value "$ZONE/trip_point_3_temp" 75000
assert_file_value "$ZONE/trip_point_4_temp" 50000
assert_file_value "$PWM_FILE" 99
printf '%s\n' 1 > "$ZONE/cdev3_trip_point"

# Do not guess the correspondence on a board with several pwm-fan devices.
mkdir -p "$SYSFS_ROOT/class/thermal/cooling_device2"
printf '%s\n' pwm-fan > "$SYSFS_ROOT/class/thermal/cooling_device2/type"
if FANCONTROL_SYSFS_ROOT="$SYSFS_ROOT" FANCONTROL_STATUS_FILE="$STATUS_FILE" \
	"$BINARY" -1 -k 0 -K 0; then
	fail "ambiguous kernel fan was selected automatically"
fi
FANCONTROL_SYSFS_ROOT="$SYSFS_ROOT" FANCONTROL_STATUS_FILE="$STATUS_FILE" \
	"$BINARY" -1 -C "$CDEV" -k 0 -K 0
assert_file_value "$ZONE/trip_point_4_temp" 50000

# user_space already delegates fan control: keep its active trips intact.
printf '%s\n' user_space > "$ZONE/policy"
printf '%s\n' 99 > "$PWM_FILE"
FANCONTROL_SYSFS_ROOT="$SYSFS_ROOT" FANCONTROL_STATUS_FILE="$STATUS_FILE" \
	"$BINARY" -C "$CDEV" -k 0 -K 0 -i 1 &
DAEMON_PID=$!
wait_for_value "$PWM_FILE" 78
assert_file_value "$ZONE/trip_point_2_temp" 100000
assert_file_value "$ZONE/trip_point_3_temp" 75000
assert_file_value "$ZONE/trip_point_4_temp" 50000
[ ! -e "$STATUS_FILE.thermal" ] || fail "user_space trips were journaled"
kill "$DAEMON_PID"
wait "$DAEMON_PID"
DAEMON_PID=""

printf '%s\n' "All fancontrol tests passed"
