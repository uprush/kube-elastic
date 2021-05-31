Searchable Snapshots with FlashBlade S3 Demo
====


```
GET /_cat/shards?h=index,shard,prirep,state,unassigned.reason

# nodes in the cluster
GET /_cat/nodes?v&h=name,disk.total,disk.used,heap.max&s=name

# Check the logstash source index
# Here we have a big number of data
GET /_cat/indices/logstash*?v&h=index,health,pri,rep,docs.count,store.size,pri.store.size&s=index

# Before doing a snapshot, we want to make sure we have a minimal number of segments
POST /logstash-2021.05.20/_forcemerge?max_num_segments=1

# We have to wait until it is done
GET /_cat/tasks?v

# Check the number of segments
GET /_cat/segments/logstash-2021.05.20?v&h=index,shard,prirep,segment,docs.count,size

# Register a repository
PUT _snapshot/reddot-s3-repo?pretty
  {
  "type": "s3",
  "settings": {
    "bucket": "deephub",
    "base_path": "elastic/snapshots",
    "endpoint": "192.168.170.11",
    "protocol": "http",
    "max_restore_bytes_per_sec": "1gb",
    "max_snapshot_bytes_per_sec": "200mb"
  }
}

# We can run a snapshot
PUT /_snapshot/reddot-s3-repo/demo
{
  "indices": "logstash-2021.05.20",
  "include_global_state": false
}

# Check the snapshot is done
GET /_cat/snapshots/reddot-s3-repo?v&h=id,status,duration,indecies,total_shards

# Recover the existing backup to index logstash-2021.05.20-fullrestore
POST /_snapshot/reddot-s3-repo/demo/_restore
{
  "indices": "logstash-2021.05.20",
  "rename_pattern": "logstash-2021.05.20",
  "rename_replacement": "logstash-2021.05.20-fullrestore"
}

# Recovery is in progress
GET /_cat/recovery/logstash-2021.05.20*/?v&h=index,time,type,stage,files_percent,bytes_recovered,bytes_percent

# This will fail until the shards are recovered
GET /logstash-2021.05.20-fullrestore/_search

# Until the recovery is done, we won't see any data with logstash-2021.05.20-fullrestore
GET /_cat/indices/logstash-2021.05.20*/?v&h=index,health,pri,rep,docs.count,store.size&s=index

# If we don't want to wait, cancel the restore operation
DELETE /logstash-2021.05.20-fullrestore

#### Enter searchable snapshots ####
# Seachable snapshots requires Elastic Enterprise license.
# Start a 30 days trial license
POST /_license/start_trial?acknowledge=true

## Recover primary shards from the snapshot (consider the snapshot as replica shards)

# Mount the snapshot
POST /_snapshot/reddot-s3-repo/demo/_mount
{
  "index": "logstash-2021.05.20",
  "renamed_index": "logstash-2021.05.20-mounted"
}

# Shards are being started
GET /_cat/shards/logstash-2021.05.20*/?v&h=index,shard,prirep,state,docs,store,node

# Recovery is in progress
GET /_cat/recovery/logstash-2021.05.20*/?v&h=index,time,type,stage,files_percent,bytes_recovered,bytes_percent

# We can start querying our index while it's recovering the primary shard behind the scene
GET /logstash-2021.05.20-mounted/_count
GET /logstash-2021.05.20-mounted/_search
{
  "query": {
    "match": {
      "kubernetes.namespace_name": "elastic"
    }
  }
}

# Searching in the local index may be a little faster...
GET /logstash-2021.05.20/_search
{
  "size": 0,
  "track_total_hits": true,
  "aggs": {
    "namespace": {
      "terms": {
        "field": "kubernetes.namespace_name.keyword"
      }
    }
  }
}

# Then searching in the snapshot. But if you run again this search after some time,
# it will be a local shard
GET /logstash-2021.05.20-mounted/_search
{
  "size": 0,
  "track_total_hits": true,
  "aggs": {
    "namespace": {
      "terms": {
        "field": "kubernetes.namespace_name.keyword"
      }
    }
  }
}

## Search directly from the snapshot (new in 7.12)

# Remove the old mounted index if exists
DELETE logstash-2021.05.20-mounted

# We are not going to recover anymore the shard locally
# But we will be using a cache on a node which can cache data.
# Set the following in elasticsearch.yaml:
# xpack.searchable.snapshot.shared_cache.size: 10gb
POST /_snapshot/reddot-s3-repo/demo/_mount?storage=shared_cache
{
  "index": "logstash-2021.05.20",
  "renamed_index": "logstash-2021.05.20-mounted"
}

# We can start querying
# It's caching files in data nodes behund the scene
GET /logstash-2021.05.20-mounted/_count
GET /logstash-2021.05.20-mounted/_search
{
  "query": {
    "match": {
      "kubernetes.namespace_name": "elastic"
    }
  }
}
GET /logstash-2021.05.20-mounted/_search
{
  "size": 0,
  "track_total_hits": true,
  "aggs": {
    "namespace": {
      "terms": {
        "field": "kubernetes.namespace_name.keyword"
      }
    }
  }
}

# We can see our shard using 0 byte on disk
GET /_cat/shards/logstash-2021.05.20*/?v&h=index,shard,prirep,state,docs,store,node

# No recovery in progress this time
GET /_cat/recovery/logstash-2021.05.20*/?v&h=index,time,type,stage,files_percent,bytes_recovered,bytes_percent

# We see all our data (the local and the snapshot)
GET /logstash-2021.05.20*/_search
{
  "size": 0,
  "track_total_hits": true,
  "query": {
    "match": {
      "stream": "stderr"
    }
  },
  "aggs": {
    "index": {
      "terms": {
        "field": "_index"
      },
      "aggs": {
        "hits": {
          "top_hits": {
            "size": 1
          }
        },
        "namespace": {
          "terms": {
            "field": "kubernetes.namespace_name.keyword"
          }
        }
      }
    }
  }
}

## Automate data tiering with Index Lifecycle Management
# We skip warm and cold tier on FlashBlade, because they are not different from hot, 
# which data is stored in FB NFS.
# Frozen tier is different because its data is on FB S3.
PUT /_ilm/policy/k8s-logs-policy
{ 
  "policy": {
    "phases" : { 
      "hot" : { 
        "actions" : { 
          "rollover" : { 
            "max_age" : "12h",
            "max_size" : "100gb" 
            }, 
          "forcemerge" : { 
            "max_num_segments" : 1 
          } 
        } 
      }, 
      "frozen" : {
        "min_age" : "2h",
        "actions" : {
          "searchable_snapshot": {
            "snapshot_repository" : "reddot-s3-repo"
          }
        } 
      }, 
      "delete" : { 
        "min_age" : "10d", 
        "actions" : { 
          "wait_for_snapshot" : {
            "policy": "daily-snapshot"
          }
        } 
      } 
    }
  }
}
```