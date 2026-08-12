#!/bin/sh

ADDR=$1
COUNT=$2
STEP=8

do_devmem2() {
	devmem2 $1 w 2>/dev/null
}

i=0
while [ $i -lt $COUNT ]; do
	CUR=$((ADDR + i * STEP))
	OUTPUT=$(do_devmem2 $CUR)
	VALUE=$(echo "$OUTPUT" | grep "Value at address" | \
			grep -o '0x[0-9A-Fa-f]*' | tail -1)
	printf "0x%08X: %s\n" $CUR "$VALUE"
	i=$((i + 1))
done
