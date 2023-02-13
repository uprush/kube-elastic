Searchable Snapshots with FlashBlade S3 Demo
====
[Elastic searchable snapshots](https://www.elastic.co/guide/en/elasticsearch/reference/current/searchable-snapshots.html) let you use snapshots to search infrequently accessed and read-only data in a very cost-effective fashion. The cold and frozen data tiers use searchable snapshots to reduce your storage and operating costs.

Elastic searchable snapshot requires enterprise license.
```bash
# Start a 30 days trial license
POST /_license/start_trial?acknowledge=true
```

# Register a FB S3 repo
```bash
# List of index and shard
GET /_cat/shards?h=index,shard,prirep,state,unassigned.reason

# nodes in the cluster
GET /_cat/nodes?v&h=name,disk.total,disk.used,heap.max&s=name

# Check the logstash source index
# Here we have a big number of data
GET /_cat/indices/elasticlogs*?v&h=index,health,pri,rep,docs.count,store.size,pri.store.size&s=index

# Before doing a snapshot, we want to make sure we have a minimal number of segments
POST /elasticlogs_q_01-000001/_forcemerge?max_num_segments=1

# We have to wait until it is done
GET /_cat/tasks?v

# Check the number of segments
GET /_cat/segments/elasticlogs_q_01-000001?v&h=index,shard,prirep,segment,docs.count,size

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
  "indices": "elasticlogs_q_01-000001",
  "include_global_state": false
}

# Check the snapshot is done
GET /_cat/snapshots/reddot-s3-repo?v&h=id,status,duration,indecies,total_shards
```

# Full restore form a snapshot
Recover the existing backup to index elasticlogs_q_01-000001-fullrestore

```bash
POST /_snapshot/reddot-s3-repo/demo/_restore
{
  "indices": "elasticlogs_q_01-000001",
  "rename_pattern": "elasticlogs_q_01-000001",
  "rename_replacement": "elasticlogs_q_01-000001-fullrestore"
}

# This will fail until the shards are recovered
GET /elasticlogs_q_01-000001-fullrestore/_search

# Recovery is in progress
GET /_cat/recovery/elasticlogs_q_01-000001*/?v&h=index,time,type,stage,files_percent,bytes_recovered,bytes_percent

# Until the recovery is done, we won't see any data with elasticlogs_q_01-000001-fullrestore
GET /_cat/indices/elasticlogs_q_01-000001*/?v&h=index,health,pri,rep,docs.count,store.size&s=index

# If we don't want to wait, cancel the restore operation
DELETE /elasticlogs_q_01-000001-fullrestore
```

# Searchable Sanpshots for frozen tier
Partially mounted index is the default for `frozen` tier by ILM when mounting a searchable snapshots.

```bash
# We are not going to recover anymore the shard locally
# But we will be using a cache on a node which can cache data.
# Set the following in elasticsearch.yaml:
# xpack.searchable.snapshot.shared_cache.size: 10gb
POST /_snapshot/reddot-s3-repo/demo/_mount?storage=shared_cache
{
  "index": "elasticlogs_q_01-000001",
  "renamed_index": "elasticlogs_q_01-000001-partialmount"
}

# Shards are being started
# We can see our shard using 0 byte on disk
GET /_cat/shards/elasticlogs_q_01-000001*/?v&h=index,shard,prirep,state,docs,store,node

# No recovery in progress this time
GET /_cat/recovery/elasticlogs_q_01-000001*/?v&h=index,time,type,stage,files_percent,bytes_recovered,bytes_percent

# We can start querying
# It's caching files in data nodes behund the scene
GET /elasticlogs_q_01-000001-partialmount/_count

# Search logs with access from Singapore
GET /elasticlogs_q_01-000001-partialmount/_search
{
  "query": {
    "match": {
      "nginx.access.geoip.country_name": "Singapore"
    }
  }
}

# Number of access by country
GET /elasticlogs_q_01-000001-partialmount/_search
{
  "size": 0,
  "track_total_hits": true,
  "aggs": {
    "namespace": {
      "terms": {
        "field": "nginx.access.geoip.country_name"
      }
    }
  }
}

# We see all our data (the local and the snapshot)
GET /elasticlogs_q_01-000001*/_search
{
  "size": 0,
  "track_total_hits": true,
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
            "field": "nginx.access.geoip.country_name"
          }
        }
      }
    }
  }
}
```


# Fully mounted snapshots
Fully mounted index is the default for `hot` and `cold` tier by ILM when mounting a snapshots.
```bash
## Recover primary shards from the snapshot (consider the snapshot as replica shards)

# Mount the snapshot
POST /_snapshot/reddot-s3-repo/demo/_mount?storage=full_copy
{
  "index": "elasticlogs_q_01-000001",
  "renamed_index": "elasticlogs_q_01-000001-fullmount"
}

# Shards are being started
GET /_cat/shards/elasticlogs_q_01-000001*/?v&h=index,shard,prirep,state,docs,store,node

# Recovery is in progress
GET /_cat/recovery/elasticlogs_q_01-000001*/?v&h=index,time,type,stage,files_percent,bytes_recovered,bytes_percent

# We can start querying our index while it's recovering the primary shard behind the scene
GET /elasticlogs_q_01-000001-fullmount/_count

# Search logs with access from Singapore
GET /elasticlogs_q_01-000001-fullmount/_search
{
  "query": {
    "match": {
      "nginx.access.geoip.country_name": "Singapore"
    }
  }
}

# Searching in the local index may be a little faster...
# Number of access by country
GET /elasticlogs_q_01-000001/_search
{
  "size": 0,
  "track_total_hits": true,
  "aggs": {
    "namespace": {
      "terms": {
        "field": "nginx.access.geoip.country_name"
      }
    }
  }
}

# Then searching in the snapshot. But if you run again this search after some time,
# it will be a local shard
GET /elasticlogs_q_01-000001-fullmount/_search
{
  "size": 0,
  "track_total_hits": true,
  "aggs": {
    "namespace": {
      "terms": {
        "field": "nginx.access.geoip.country_name"
      }
    }
  }
}

## Search directly from the snapshot (new in 7.12)

# Remove the old mounted index if exists
DELETE elasticlogs_q_01-000001-fullmount
```

## Automate data tiering with Index Lifecycle Management
We skip warm and cold tier on FlashBlade, because they are not different from hot, which data is stored in FB NFS.
Frozen tier is different because its data is on FB S3.

```bash
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
        "min_age" : "3d",
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