#!/usr/bin/env bash
# CLASSIFY RESULTS BASED ON CRASH OUTPUT
FUZZER=$1
FUZZER=$(basename $FUZZER)


function dump_crash() {
    # use folder as $1 
    # count total number of crashes in the dir first
    
    N_CR=$(find $1 -type f | wc -l)
    
    # if specified, add suffix (depending on $2)
    if [ -n "$2" ]; then
        # echo "# Suffix: $2"
        N_CR=$(find $1 -type f -name "*134" | wc -l)
        INPUTS=$(find $1 -type f | grep "\.$2$" | sort -u)
    else

        INPUTS=$(find $1 -type f | sort -u)
    fi
    echo "# CRASHES for FUZZER  $FUZZER in folder $1: $N_CR"

    for c in $INPUTS; do
        # if the file is the current directory itself or README, then skip
        if [ "$c" == "$1/README.txt" ]; then
                continue
        fi
        if [ "$c" == "$1/" ]; then
                continue
        fi
        # if the file has * in the name, skip it
        if [[ "$c" == *"*"* ]]; then
                continue
        fi
        
        # OUTPUT=`timeout -s TERM 6s  /out/$FUZZER $c 2>&1`
        # if [ "$?" -eq 0 ]; then
        # # NO REPRO
        #     echo "INPUT: $c 
        #      NO REPRO"
        #     continue
        # fi
        OUTPUT=`timeout -s TERM 10s /out/$FUZZER $c 2>&1`
        rc=$?
        wait $!
        if [ $rc -eq 0 ]; then
            # echo "INPUT: $c 
            #  NO REPRO"
            continue
        fi

        MISM=`echo "$OUTPUT" | grep SUMM | grep mism`
        OTHER=`echo "$OUTPUT" | grep ERROR`
        # sometimes it's different - no ERROR, just CHECK
        CHECK_OUT=`echo "$OUTPUT" | grep CHECK| sed 's/tid=[0-9]\+//g'`
        # OTHER:   HWAddressSanitizer: CHECK failed: sanitizer_allocator_secondary.h:177 "((IsAligned(reinterpret_cast<uptr>(p), page_size_))) != (0)" (0x0, 0x0) (tid=45148)
        OTHER_SUMM=`echo "$OUTPUT" | grep SUMM | grep -v mism`
        ASSERT=`echo "$OUTPUT" | grep ASSERT`
        # concat ASSERT with "grep ssert" output 
        ASSERT2=`echo "$OUTPUT" | grep ssert`
        # libc++ exceptions
        EXC=`echo "$OUTPUT" | grep "xception"`

        if [ -n "$MISM" ]; then
        echo "INPUT: $c 
             MISM: $MISM"
        else
        echo "INPUT: $c 
             OTHER: $OTHER $OTHER_SUMM $CHECK_OUT $ASSERT $ASSERT2 $EXC"
        fi
    done
}

dump_crash /crashes-${FUZZER} 134
dump_crash /fuzzing-campaign/${FUZZER}_0/default/crashes