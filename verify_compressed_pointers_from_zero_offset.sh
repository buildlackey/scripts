#!/bin/bash

COMPILED_SCRIPT_DIR=~/.elastic_search
mkdir -p $COMPILED_SCRIPT_DIR

cat <<EOF >/$COMPILED_SCRIPT_DIR/CompressedOopsInfo.java
/**
 * This script applies the helpful advice that this blog  -- https://www.elastic.co/blog/a-heap-of-trouble#ref5 -- 
 * offers regarding the benefits of sizing one's Java heap so that (a) compressed pointers can be used 
 * (for heaps under 32GB) and (b) the sum of start address and heap size is below the 32GiB threshold, 
 * which allows for zero based addressing.  
 *
 * The article explains  how (a) compressed pointers allow more efficient use of heap space, and (b) how one's 
 * machine architecture determines the exact heap size cut-off point at which zero based addressing is no 
 * longer possible, and (c)  how inability to perform zero based addressing increases the amount of arithmetic necessary 
 * to resolve pointer addresses. Finally, the article recommends the use of JVM options -XX:+UnlockDiagnosticVMOptions 
 * -XX:+PrintCompressedOopsMode to enable log output either like this:
 * 
 *     heap address: 0x000000011be00000, size: 27648 MB, zero based Compressed Oops
 * 
 * which indicates zero-based compressed oops are enabled, or output like this
 * 
 *      heap address: 0x0000000118400000, size: 28672 MB, Compressed Oops with base: 0x00000001183ff000
 * 
 * which indicates that the heap begins at an address other than zero, therefore requiring the aforementioned 
 * increase amount of arithmetic processing. 
 * 
 * Since it is not always possible or easy to figure out where to inject those JVM options this script 
 * provides an alternative. You run the script (as ROOT so you have the appropriate permissions) with 
 * the pid of a Java program whose compressed pointer enablement you wish to ascertain.
 *      
 * Example run (assuming your checking an Elasticsearch process:
 *      
 *      sudo ps axuw | grep "java.*elastic" | grep -v grep | cut -c9-14 | \
 *          sudo xargs  bash verify_compressed_pointers_from_zero_offset.sh
 *      
 * CAVEAT:  if you ever tweak or update this script be sure to bow away COMPILED_SCRIPT_DIR !
 *      
 */

import sun.jvm.hotspot.runtime.VM;
import sun.jvm.hotspot.tools.Tool;

public class CompressedOopsInfo extends Tool {

    @Override
    public void run() {
        VM vm = VM.getVM();
        System.out.println("CompressedOops = " + vm.isCompressedOopsEnabled());
        System.out.println("CompressedClassPointers = " + vm.isCompressedKlassPointersEnabled());
        System.out.println("OOP base = 0x" + Long.toHexString(vm.getDebugger().getNarrowOopBase()));
        System.out.println("OOP shift = " + vm.getDebugger().getNarrowOopShift());
    }

    public static void main(String[] args) {
        new CompressedOopsInfo().execute(args);
    }
}

EOF

USAGE="bash $0 <PID_OF_JAVA_PROCESS_TO_CHECK>  [path to JAVA_HOME]"

PID_OF_JAVA_PROCESS_TO_CHECK=$1
if [ "$PID_OF_JAVA_PROCESS_TO_CHECK" = "" ] ; then 
    echo ERROR only java 1.8 and 1.9 are supported by this script
    exit 1
fi

if [ "$2" != "" ] ; then 
    export JAVA_HOME=$2
fi

VERS=`java -version  2>&1 | grep version  | egrep '"1.8|"1.9'   | \
                sed -e's/java version "//' | sed -e 's/^1.8.*/1.8/'  | sed -e 's/^1.9.*/1.9/'`

if [ "$VERS" = "1.8" ] ; then
    CP=" -cp .:$JAVA_HOME/lib/sa-jdi.jar "
elif [ "$VERS" = "1.9" ] ; then
    CP=" -cp . "
else 
    echo ERROR only java 1.8 and 1.9 are supported by this script
    exit 1
fi


if [ ! -e  "$COMPILED_SCRIPT_DIR/CompressedOopsInfo.o" ] ; then 
     ( cd $COMPILED_SCRIPT_DIR ; javac $CP CompressedOopsInfo.java )
fi

probeResultFile=/tmp/$0.result.$$
( cd $COMPILED_SCRIPT_DIR ;  java $CP  CompressedOopsInfo $PID_OF_JAVA_PROCESS_TO_CHECK > $probeResultFile)


EXIT_STATUS=0

cat $probeResultFile | grep 'CompressedClassPointers = true'
if [ "$?" != "0" ] ; then
    echo WARNING compressed pointers do not seem to be enabled - heap over 32GB
    EXIT_STATUS=1
fi



cat $probeResultFile | grep 'OOP base = 0x0'
if [ "$?" != "0" ] ; then
    echo WARNING zero based addressing does not seem to be enabled - maybe shrink heap a bit ?
    EXIT_STATUS=1
fi

rm -rf $probeResultFile
exit $EXIT_STATUS

