#!/bin/bash
region=eu-central-1
version='1.27'
cidr='10.0.0.0/16'
node_type='t3.medium'

usage() {
  cat << EOF
Usage:
    To Start Cluster:
    $0 -c [name of the cluster]

    to Destroy Cluster:
    $0 -d [name of the cluster]

Examples:
    ./cluster.sh -c eks-2023
    ./cluster.sh -d eks-2023
EOF
}

create_cluster() {
  local cluster_name=$1
  local region=$2
  local version=$3
  local vpccidr=$4
  local node_type=$5

  eksctl create cluster \
    --name $cluster_name \
    --region $region  \
    --version ${version} \
    --zones ${region}a,${region}b \
    --vpc-cidr ${vpccidr} \
    --without-nodegroup

  eksctl utils associate-iam-oidc-provider \
    --region  $region  \
    --cluster $cluster_name \
    --approve

  eksctl create nodegroup --cluster=${cluster_name} \
    --region=$region  \
    --name=${cluster_name}-ng-public1 \
    --node-type=${node_type} \
    --nodes=2 \
    --nodes-min=2 \
    --nodes-max=4 \
    --node-volume-size=20 \
    --ssh-access \
    --ssh-public-key=eks \
    --managed \
    --asg-access \
    --external-dns-access \
    --full-ecr-access \
    --appmesh-access \
    --alb-ingress-access
}

install_ingress_nginx() {
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
  helm upgrade --install ingress-nginx ingress-nginx \
    --repo https://kubernetes.github.io/ingress-nginx  \
    --namespace ingress-nginx \
    --create-namespace \
    --set-string controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"="nlb"
}

destroy_ingress_nginx() {
  helm uninstall ingress-nginx -n ingress-nginx
}

delete_cluster() {
  local cluster_name=$1
  local region=$2

  while true; do
      read -p "Do you really want to delete the cluster '${cluster_name}'? (Yes/No) " yn
      case $yn in
          [Yy]* ) break;;  # If yes, break the loop and continue with deletion
          [Nn]* ) echo "Cluster deletion cancelled."; return;;
          * ) echo "Please answer Yes or No.";;
      esac
  done
  eksctl delete nodegroup --region=$region  --cluster=${cluster_name} --name=${cluster_name}-ng-public1
  eksctl delete cluster   --region=$region  --name=${cluster_name}
}



if [ $# -eq 0 ]; then
    echo "No arguments provided."
    usage
fi

while getopts "c:d:" OPTKEY; do
    case "${OPTKEY}" in
        'c')
            printf "Creating Cluster ${OPTARG}\n"
            create_cluster ${OPTARG} ${region} ${version} ${cidr} ${node_type}
            sleep 10
            install_ingress_nginx
          ;;
        'd')
            printf "Deleting Cluster ${OPTARG}\n"
            destroy_ingress_nginx
            delete_cluster ${OPTARG} ${region}
          ;;
        ':')
            printf "\nERROR: MISSING ARGUMENT for option -- ${OPTARG}"
            exit 1
            ;;
        *)
            usage && exit 1
            ;;
    esac
done
shift $((OPTIND-1))
