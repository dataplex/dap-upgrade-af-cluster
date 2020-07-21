#!/usr/bin/env bash

. config.sh

docker exec $CONTAINER_NAME \
	evoke configure master \
    	--accept-eula \
    	-h $MASTER1_EXT \
    -p $ADMIN_PASS \
    --master-altnames="$MASTER1_EXT,$MASTER2_EXT,$MASTER3_EXT" \
    $ORG_NAME
