FROM docker.elastic.co/elasticsearch/elasticsearch:8.4.2

# Install s3 repository
RUN bin/elasticsearch-plugin install --batch repository-s3
