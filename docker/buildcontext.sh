#!/bin/bash

echo "Preparing kaniko build context"
rm -rf build
mkdir build
cp elasticsearch.Dockerfile build/Dockerfile
tar cfvz build.tar.gz build

echo "Uploading build context"
aws s3 --endpoint-url=http://10.226.224.247 --profile fb cp build.tar.gz s3://yifeng/kaniko/build.tar.gz

echo "Done"
