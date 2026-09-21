#!/bin/sh
# NanoPi R4S fan control (PWM1 @ ff420010 -> /sys/class/pwm/pwmchip1/pwm0)
# Temperature curve based on cpu-thermal (thermal_zone0), polled every 5s.
# Duty table (percent of PWM period):
#   < 45C : 30%   (always spinning, quiet)
#   45-55 : 50%
#   55-62 : 75%
#   >= 62 : 100%
# Hysteresis: only step down when 3C below the threshold that raised it.

CHIP=/sys/class/pwm/pwmchip1
PWM=$CHIP/pwm0
TEMP=/sys/class/thermal/thermal_zone0/temp
PERIOD=50000
INTERVAL=5
STATE=/var/run/fanctl.state

[ -d "$PWM" ] || echo 0 > $CHIP/export
sleep 1
echo 0 > $PWM/enable 2>/dev/null
echo normal > $PWM/polarity
echo $PERIOD > $PWM/period
echo $PERIOD > $PWM/duty_cycle     # start at 100% for 3s as a self-test
echo 1 > $PWM/enable
sleep 3

cur=-1
level=0
while :; do
    t=$(cat $TEMP 2>/dev/null); t=${t:-60000}
    tc=$((t / 1000))
    new=$level
    case $level in
        0) [ $tc -ge 45 ] && new=1 ;;
        1) [ $tc -ge 55 ] && new=2; [ $tc -lt 42 ] && new=0 ;;
        2) [ $tc -ge 62 ] && new=3; [ $tc -lt 52 ] && new=1 ;;
        3) [ $tc -lt 59 ] && new=2 ;;
    esac
    # safety: jump straight to 100% if very hot
    [ $tc -ge 70 ] && new=3
    level=$new
    case $level in
        0) pct=30 ;; 1) pct=50 ;; 2) pct=75 ;; *) pct=100 ;;
    esac
    duty=$((PERIOD * pct / 100))
    if [ "$duty" != "$cur" ]; then
        echo $duty > $PWM/duty_cycle
        cur=$duty
        logger -t fanctl "temp=${tc}C fan=${pct}%"
    fi
    echo "temp=${tc}C fan=${pct}%" > $STATE
    sleep $INTERVAL
done
