.DEFAULT_GOAL := build-es

REGISTRY = 'harbor.purestorage.int/reddot'
BUILD_VER = '7.15.1'

build-es:
	@echo "Building Elasticsearch image"
	docker build -t elasticsearch:${BUILD_VER} -f ./elasticsearch.Dockerfile .
	docker tag elasticsearch:${BUILD_VER} ${REGISTRY}/elasticsearch:${BUILD_VER}
	docker push ${REGISTRY}/elasticsearch:${BUILD_VER}
