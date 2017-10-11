#!/bin/bash

COMPILED_SCRIPT_DIR=~/.elastic_search
mkdir -p $COMPILED_SCRIPT_DIR

cat <<EOF >/$COMPILED_SCRIPT_DIR/EnumerateShardingOptions.java
/**
 * Given a cluster's estimated data size in gigabytes, this utility enumerates sharding options for that cluster
 * (with each option detailing number of shards, GB per shard, number of nodes, and for convenience, the ratio of
 * shards per node.)   This utility makes recommendations only in terms of primary shards: no estimate of
 * ideal number of replicas is attempted.
 *
 * The following constraints are observed in enumerating options:
 * <ul>
 *     <li>
 *         number of nodes in any cluster is assumed to be an integral multiple of 3
 *     </li>
 *     <li>
 *         size of a shard must be >= 1GB and <= 25GB
 *     </li>
 *     <li>
 *         the maximum number of nodes cluster  in  a cluster is assumed to be 200
 *     </li>
 * </ul>
 *
 *
 *  Each proposed shard size constrains the number of shards for that configuration, however for a a given shard
 *  size and associated (fixed) number of shards it is possible to distribute those shards over a cluster
 *  comprised of varying cardinality of data nodes: from 3 up to the max cluster size we allow.
 *
 *  The utility makes no recommendation as to the optimal cluster size, the user needs to take into
 *  account factors such as the type of machines the cluster will run on, and rules of thumb such
 *  as 'the higher the number of data nodes, the more performant the cluster will be, but at a higher cost'.
 *
 *  Implementation:
 *
 *      (i)   We set numShards=3 shards and divide  dataSizeInGB by numShards until the quotient is <= 25GB,
 *      increasing numShards by 3 each time.
 *
 *      (ii) At this point numShards is large enough to ensure that data size per shards is <= 25GB, and we
 *      have our first candidate configuration in terms of numShards.
 *
 *      (iii) Each 'numShards' candidate  configuration  is characterized primarily by "(estimated) shard size
 *      plus number of shards", but we also list variants of that configuration, where each variant differs by #
 *      of dataNodes. We start at #dataNodes=3 and continue until #dataNodes = numShards (i. e. until
 *      we arrive at an option for which the number of primary shards == # data nodes.)
 *
 *      Next, we increment numShards by 3 again, and if dataSizeInGB / numShards is still >= 1GB we consider
 *      this another valid candidate configuration, and we proceed again from step iii.
 */
public class EnumerateShardingOptions {
    public static final double MAX_GB_PER_SHARD = 25D;
    public static final double MIN_GB_PER_SHARD = 1D;
    public static final double MAX_NODES_PER_CLUSTER = 200;


    public static void main(String[] args) throws Exception {
        System.out.println();
        new EnumerateShardingOptions().run(args);
    }

    public void run(String[] args) throws Exception {
        if (args.length < 1) {
            usage();
        }

        Long dataSizeInGB;
        try {
            dataSizeInGB = Long.parseLong(args[0]);
        } catch (Exception e) {
            usage();
            throw (e);
        }

        if (dataSizeInGB < 3) {
            System.out.println("For data size of 3GB or less use 3 shards and a cluster size of 3 nodes");
        }

        generateShardingOptions(dataSizeInGB);
    }


    private static void generateShardingOptions(double dataSizeInGB) {
        int numShards = 3;

        while (dataSizeInGB / numShards > MAX_GB_PER_SHARD) {
            numShards = numShards + 3;
        }

        while (dataSizeInGB / numShards >= MIN_GB_PER_SHARD ) {

            double shardSize = dataSizeInGB / (numShards * 1.0F);

            System.out.printf("numShards: %3d   ShardSize: %.2f\n",  numShards,shardSize);
            long numDataNodes = 3;
            do {
                if (numShards  % numDataNodes == 0) {
                    System.out.printf(
                            "\tdataNodes: %3d   shards/dataNode: %d",
                            numDataNodes,
                            numShards / numDataNodes);

                    System.out.println();

                }
                numDataNodes =  numDataNodes + 3;
            } while (numDataNodes <= numShards && numDataNodes <= MAX_NODES_PER_CLUSTER);

            numShards = numShards + 3;
        }
    }



    private static void usage() {
        System.out.println("Usage:  sharding_options_given_cluster_size.sh <dataSizeInGB>.");

        System.exit(1);
    }
}
EOF




dataSizeInGB=$1

if [ ! -e  "$COMPILED_SCRIPT_DIR/EnumerateShardingOptions.o" ] ; then 
    ( cd $COMPILED_SCRIPT_DIR ; javac EnumerateShardingOptions.java )
fi

( cd $COMPILED_SCRIPT_DIR ;  java EnumerateShardingOptions $dataSizeInGB )


