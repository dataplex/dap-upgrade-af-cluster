#!/usr/bin/env bash

. config.sh

showHeader "Step 8: U5ish: Determine Async Standby"

ASYNC_INT=$(curl -sk https://$MASTER1_EXT/health | \
	jq -r '.database.replication_status.pg_stat_replication[] | 
	select(.sync_state=="potential") | 
		.client_addr')

ASYNC_EXT=$(curl -sk https://$ASYNC_INT/info | \
	jq -r '.configuration.conjur.hostname')

echo "---- ASYNC Standby -- EXT: $ASYNC_EXT   INT: $ASYNC_INT"

showHeader "Step 9: U2: Stop Replication on Standbys"

ssh -i $SSH_KEY $SSH_USER@$MASTER2_INT \
	"docker exec $CONTAINER_NAME evoke replication stop"
ssh -i $SSH_KEY $SSH_USER@$MASTER3_INT \
	"docker exec $CONTAINER_NAME evoke replication stop"

showHeader "Step 10: U3: Generate Seed Files... nahh... already done in previous step. Reuse."

showHeader "Step 11: U5-2: Remove Async Standby From AF Cluster"

ssh -i $SSH_KEY $SSH_USER@$MASTER1_INT \
	"docker exec $CONTAINER_NAME evoke cluster member remove $ASYNC_EXT"

showHeader "Step 12: U6-A: 'Stop' DAP Container on Async Standby... we delete."

ssh -i $SSH_KEY $SSH_USER@$ASYNC_INT "docker rm -f $CONTAINER_NAME"

showHeader "Step 13: U6-B: Start New Container Version: $TO_VERSION"

ssh -i $SSH_KEY $SSH_USER@$ASYNC_INT "./runmaster.sh $TO_VERSION"

showHeader "Step 14: U6-C_D: Configure Standby w/ Seed File"

ssh -i $SSH_KEY $SSH_USER@$ASYNC_INT \
	"cat *.seed | docker exec -i $CONTAINER_NAME evoke unpack seed -"

ssh -i $SSH_KEY $SSH_USER@$ASYNC_INT \
	"docker exec $CONTAINER_NAME evoke configure standby"

showHeader "Step 15: U7: Add Cluster Member Back"

ssh -i $SSH_KEY $SSH_USER@$MASTER1_INT \
	"docker exec $CONTAINER_NAME evoke cluster member add $ASYNC_EXT"

showHeader "Step 16: U8: Re-enroll the standby into the AF cluster"

ssh -i $SSH_KEY $SSH_USER@$ASYNC_INT \
	"docker exec $CONTAINER_NAME evoke cluster enroll --reenroll -n $ASYNC_EXT -m $MASTER1_EXT $CLUSTER_NAME"

showHeader "Step 17: U9: Repeat for other standby..."

SYNC_INT=$(echo "$MASTER2_INT$MASTER3_INT" | sed "s/$ASYNC_INT//g")
SYNC_EXT=$(curl -sk https://$SYNC_INT/info | jq -r '.configuration.conjur.hostname')

# Damn...that's clever stuff!

ssh -i $SSH_KEY $SSH_USER@$MASTER1_INT \
	"docker exec $CONTAINER_NAME evoke cluster member remove $SYNC_EXT"

ssh -i $SSH_KEY $SSH_USER@$SYNC_INT "docker rm -f $CONTAINER_NAME"
ssh -i $SSH_KEY $SSH_USER@$SYNC_INT "./runmaster.sh $TO_VERSION"
ssh -i $SSH_KEY $SSH_USER@$SYNC_INT \
	"cat *.seed | docker exec -i $CONTAINER_NAME evoke unpack seed -"

ssh -i $SSH_KEY $SSH_USER@$SYNC_INT \
	"docker exec $CONTAINER_NAME evoke configure standby"

ssh -i $SSH_KEY $SSH_USER@$MASTER1_INT \
	"docker exec $CONTAINER_NAME evoke cluster member add $SYNC_EXT"

ssh -i $SSH_KEY $SSH_USER@$SYNC_INT \
	"docker exec $CONTAINER_NAME evoke cluster enroll --reenroll -n $SYNC_EXT -m $MASTER1_EXT $CLUSTER_NAME"

showHeader "Step 18: U10: Stop the master server and wait for failover to occur"

ssh -i $SSH_KEY $SSH_USER@$MASTER1_INT \
	"docker rm -f $CONTAINER_NAME"

master_msg="acting as master"
NEWMASTER_INT=""
NEWMASTER_EXT=""
while true
do
	for i in $MASTER2_INT $MASTER3_INT; do
		if [ "$(curl -sk https://$i/health | grep "$master_msg")" != "" ];then
			NEWMASTER_INT="$i"
			NEWMASTER_EXT="$(curl -sk https://$i/info | jq -r .configuration.conjur.hostname)"
		fi
	done

	if [ "$NEWMASTER_INT" != "" ]; then
		echo "Found new master: $NEWMASTER_INT"
		break
	else
		echo "Failover has not occurred...sleeping 10"
		sleep 10
	fi
done

showHeader "Step 19: U11-A: Start container on new standby (old master)"

ssh -i $SSH_KEY $SSH_USER@$MASTER1_INT \
	"./runmaster.sh $TO_VERSION"

showHeader "Step 20: U11-B: Generate seed file and configure standby"

ssh -i $SSH_KEY $SSH_USER@$NEWMASTER_INT \
	"docker exec $CONTAINER_NAME evoke seed standby $MASTER1_EXT $NEWMASTER_EXT" > standby1.seed

scp -i $SSH_KEY standby1.seed $SSH_USER@$MASTER1_INT:.

ssh -i $SSH_KEY $SSH_USER@$MASTER1_INT \
	"cat ./standby1.seed | docker exec -i $CONTAINER_NAME evoke unpack seed -"

ssh -i $SSH_KEY $SSH_USER@$MASTER1_INT \
	"docker exec -i $CONTAINER_NAME evoke configure standby"

showHeader "Step 21: U11-D_E: Re-add and re-enroll new standby into AF cluster"

ssh -i $SSH_KEY $SSH_USER@$NEWMASTER_INT \
	"docker exec $CONTAINER_NAME evoke cluster member add $MASTER1_EXT"

ssh -i $SSH_KEY $SSH_USER@$MASTER1_INT \
	"docker exec $CONTAINER_NAME evoke cluster enroll --reenroll -n $MASTER1_EXT -m $NEWMASTER_EXT $CLUSTER_NAME"

showHeader "Step 22: U12: Check health of nodes, specifically cluster health"

while true;
do
	m1_af_status=$(curl -sk https://$MASTER1_INT/health | jq -cr '.cluster.status')
	echo -n "MASTER1: $m1_af_status "
	m2_af_status=$(curl -sk https://$MASTER2_INT/health | jq -cr '.cluster.status')
	echo -n "MASTER2: $m2_af_status "
	m3_af_status=$(curl -sk https://$MASTER3_INT/health | jq -cr '.cluster.status')
	echo "MASTER3: $m3_af_status"
	c_stat="$(echo "$m1_af_status$m2_af_status$m3_af_status" | sed 's/running//g' | sed 's/standing_by//g')"


	if [ "$c_stat" != "" ]; then
		echo "Waiting for AF cluster to refresh... Sleeping 10..."
		sleep 10
	else
		echo -e "\n\nCluster is fully operational... time to upgrade it!"
		break
	fi
done

showHeader "Step 23: U?: Re-enable synchronous replication for standby servers"

ssh -i $SSH_KEY $SSH_USER@$MASTER1_INT \
	"docker exec $CONTAINER_NAME evoke replication sync enable"

OTHERSTANDBY="$(echo "$MASTER2_INT$MASTER3_INT" | sed "s/$NEWMASTER_INT//g")"

ssh -i $SSH_KEY $SSH_USER@$OTHERMASTER \
	"docker exec $CONTAINER_NAME evoke replication sync enable"

ssh -i $SSH_KEY $SSH_USER@$NEWMASTER_INT \
	"docker exec $CONTAINER_NAME evoke replication sync start"

sleep 2 # Let it catch up!

curl -sk https://$NEWMASTER_INT/health | \
	jq -cr '.database.replication_status.pg_stat_replication[] | { IP: .client_addr, sync: .sync_state }'
	
showHeader "STEP DOOOOOOOONNNNEEEEEEE!!!!!!!!!!!"
