FROM docker.elastic.co/elasticsearch/elasticsearch:7.15.1

# Install s3 repository
RUN bin/elasticsearch-plugin install --batch repository-s3
