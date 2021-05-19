ElasticSearch with Kubernetes
=============================

Code snippets and notes on running Apache Spark with Kubernetes.

Install Elastic Cloud on Kubbernetes Operator
```
kubectl apply -f https://download.elastic.co/downloads/eck/1.5.0/all-in-one.yaml
```

Create a Elastic cluster:
```
kubectl apply -f reddot.yaml
```

# Snapshot to S3
Reference:
* [A Guide to Elasticsearch Snapshots](https://joshua-robinson.medium.com/a-guide-to-elasticsearch-snapshots-565017630638)

## Install S3 snapshot repository

Create a secret for S3 access keys:
```
kubectl create secret generic es-s3-keys -n elastic --from-literal=access-key='xxxx' --from-literal=secret-key='vvvv'
```

Install S3 repository plugin:
```
kubectl apply -f reddot.yaml
```

Go to Kibana [Stack Management UI](https://kibana.purestorage.int:16444/app/kibana#/management/elasticsearch/snapshot_restore/add_repository) to register the repository.

## Create S3 repository
Create a FB S3 repository:
```
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
```

Check repositories on [Repositories UI](https://kibana.purestorage.int:16444/app/kibana#/management/elasticsearch/snapshot_restore/repositories).

## Create snapshots
Create a snapshot policy on [Stack Management UI](https://kibana.purestorage.int:16444/app/kibana#/management/elasticsearch/snapshot_restore/policies).


# Demo
Demo flow:
1. k8s cluster walk through, PSO storage class
2. k8s logging with Elastic & FB: search 'error', dashboard
3. Scale Elastic: data node count, pure-file, FB UI
4. Snapshot to S3: repo setting, s3 ls

```
s3 ls s3://deephub/elastic/snapshots/
```
