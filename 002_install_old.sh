#!/usr/bin/env bash

. config.sh

showHeader "Step 1: RESET - Delete all containers and seed files"

ssh -i $SSH_KEY $SSH_USER@$MASTER1_INT "docker rm -f $CONTAINER_NAME; rm -f *.seed"
ssh -i $SSH_KEY $SSH_USER@$MASTER2_INT "docker rm -f $CONTAINER_NAME; rm -f *.seed"
ssh -i $SSH_KEY $SSH_USER@$MASTER3_INT "docker rm -f $CONTAINER_NAME; rm -f *.seed"

showHeader "Step 2: Stage Start Script and Config File"

for i in runmaster.sh config.sh;do
	scp -i $SSH_KEY $i $SSH_USER@$MASTER1_INT:.
	scp -i $SSH_KEY $i $SSH_USER@$MASTER2_INT:.
	scp -i $SSH_KEY $i $SSH_USER@$MASTER3_INT:.
done

showHeader "Step 3: Start and Configure Master"

ssh -i $SSH_KEY $SSH_USER@$MASTER1_INT "./runmaster.sh $FROM_VERSION"

scp -i $SSH_KEY config_master.sh $SSH_USER@$MASTER1_INT:.
ssh -i $SSH_KEY $SSH_USER@$MASTER1_INT "./config_master.sh"

showHeader "Step 4: Generate Seed Files and Configure Standby Servers"

SEED_NAME="standby2.seed"
ssh -i $SSH_KEY $SSH_USER@$MASTER1_INT "docker exec dap evoke seed standby $MASTER2_EXT $MASTER1_EXT" > $SEED_NAME
scp -i $SSH_KEY $SEED_NAME $SSH_USER@$MASTER2_INT:.
ssh -i $SSH_KEY $SSH_USER@$MASTER2_INT "./runmaster.sh $FROM_VERSION"
ssh -i $SSH_KEY $SSH_USER@$MASTER2_INT "docker cp ./$SEED_NAME $CONTAINER_NAME:/"
ssh -i $SSH_KEY $SSH_USER@$MASTER2_INT "docker exec $CONTAINER_NAME evoke unpack seed /$SEED_NAME"
ssh -i $SSH_KEY $SSH_USER@$MASTER2_INT "docker exec $CONTAINER_NAME evoke configure standby"
ssh -i $SSH_KEY $SSH_USER@$MASTER2_INT "docker exec $CONTAINER_NAME evoke replication sync enable"

SEED_NAME="standby3.seed"
ssh -i $SSH_KEY $SSH_USER@$MASTER1_INT "docker exec $CONTAINER_NAME evoke seed standby $MASTER3_EXT $MASTER1_EXT" > $SEED_NAME
scp -i $SSH_KEY $SEED_NAME $SSH_USER@$MASTER3_INT:.
ssh -i $SSH_KEY $SSH_USER@$MASTER3_INT "./runmaster.sh $FROM_VERSION"
ssh -i $SSH_KEY $SSH_USER@$MASTER3_INT "docker cp ./$SEED_NAME $CONTAINER_NAME:/"
ssh -i $SSH_KEY $SSH_USER@$MASTER3_INT "docker exec $CONTAINER_NAME evoke unpack seed /$SEED_NAME"
ssh -i $SSH_KEY $SSH_USER@$MASTER3_INT "docker exec $CONTAINER_NAME evoke configure standby"
ssh -i $SSH_KEY $SSH_USER@$MASTER3_INT "docker exec $CONTAINER_NAME evoke replication sync enable"


ssh -i $SSH_KEY $SSH_USER@$MASTER1_INT "docker exec $CONTAINER_NAME evoke replication sync start"

showHeader "Step 5: Configure Cluster Policy"

cat cluster.yaml.template | \
	sed "s/{{CLUSTER_NAME}}/$CLUSTER_NAME/g" |
	sed "s/{{MASTER1_HOST}}/$MASTER1_EXT/g" |
	sed "s/{{MASTER2_HOST}}/$MASTER2_EXT/g" |
	sed "s/{{MASTER3_HOST}}/$MASTER3_EXT/g" \
	> cluster.yaml

./loadclusterpolicy.sh

showHeader "Step 6: Enroll Cluster Members"

ssh -i $SSH_KEY $SSH_USER@$MASTER1_INT \
	"docker exec $CONTAINER_NAME evoke cluster enroll -n $MASTER1_EXT $CLUSTER_NAME" 
ssh -i $SSH_KEY $SSH_USER@$MASTER2_INT \
	"docker exec $CONTAINER_NAME evoke cluster enroll -n $MASTER2_EXT -m $MASTER1_EXT $CLUSTER_NAME" 
ssh -i $SSH_KEY $SSH_USER@$MASTER3_INT \
	"docker exec $CONTAINER_NAME evoke cluster enroll -n $MASTER3_EXT -m $MASTER1_EXT $CLUSTER_NAME" 

showHeader "Step 7: Check Health of Current Version: $FROM_VERSION"

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
