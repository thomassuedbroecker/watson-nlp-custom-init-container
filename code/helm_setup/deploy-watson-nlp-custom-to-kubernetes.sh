#!/bin/bash

# **************** Global variables
source ./.env

export HELM_RELEASE_NAME=watson-nlp-custom
export DEFAULT_NAMESPACE="default"
export CR_NAMESPACE="custom-watson-nlp-tsued"
export CE_PROJECT_NAME="custom-watson-nlp-tsued"
export WATSON_NLP_CONTAINER=watson-nlp-custom

######### Watson NLP custom model container image ##############
CUSTOM_WATSON_NLP_IMAGE_NAME=watson-nlp_ensemble_model
CUSTOM_TAG=1.0.0

######### IBM Cloud Container registry for custom image ##############
CR_CUSTOM_REGISTRY_URL=us.icr.io

# **********************************************************************************
# Functions definition
# **********************************************************************************

function loginIBMCloud () {
    
    echo ""
    echo "*********************"
    echo "loginIBMCloud"
    echo "*********************"
    echo ""

    ibmcloud login --apikey $IC_API_KEY
    ibmcloud target -r $REGION
    ibmcloud target -g $GROUP
}

function configureIBMCloudRegistry () {
    echo ""
    echo "# ******"
    echo "# Configure IBM Cloud Registry"
    echo "# ******"
    echo ""

    ibmcloud cr region-set $CR_CUSTOM_REGISTRY_URL
    ibmcloud cr namespace-add $CR_NAMESPACE
    docker login -u iamapikey -p $IC_API_KEY $CR_CUSTOM_REGISTRY_URL
    ibmcloud cr login
}

function uploadCustomImageToIBMCloudRegistry () {
    # Tag the image
    echo "Container image: ${CR_CUSTOM_REGISTRY_URL}/${CR_NAMESPACE}/$CUSTOM_WATSON_NLP_IMAGE_NAME:$CUSTOM_TAG"
    docker tag $CUSTOM_WATSON_NLP_IMAGE_NAME:$CUSTOM_TAG ${CR_CUSTOM_REGISTRY_URL}/${CR_NAMESPACE}/$CUSTOM_WATSON_NLP_IMAGE_NAME:$CUSTOM_TAG

    # Push the image
    docker push ${CR_CUSTOM_REGISTRY_URL}/${CR_NAMESPACE}/$CUSTOM_WATSON_NLP_IMAGE_NAME:$CUSTOM_TAG
}

function connectToCluster () {

    echo ""
    echo "*********************"
    echo "connectToCluster"
    echo "*********************"
    echo ""

    ibmcloud ks cluster config -c $CLUSTER_ID
    kubectl config current-context
}

function createDockerCustomConfigFile () {

    echo ""
    echo "*********************"
    echo "createDockerCustomConfigFile"
    echo "*********************"
    echo ""

    echo "- custom_config.json"
    sed "s+IBM_ENTITLEMENT_KEY+$IBM_ENTITLEMENT_KEY+g;s+IBM_ENTITLEMENT_EMAIL+$IBM_ENTITLEMENT_EMAIL+g;s+IC_EMAIL+$IC_EMAIL+g;s+IC_API_KEY+$IC_API_KEY+g;s+CR_CUSTOM_REGISTRY_URL+$CR_CUSTOM_REGISTRY_URL+g" "$(pwd)/custom_config.json_template" > "$(pwd)/custom_config.json"
    IBM_ENTITLEMENT_SECRET=$(base64 -i "$(pwd)/custom_config.json")
    echo "IBM_ENTITLEMENT_SECRET: $IBM_ENTITLEMENT_SECRET"
    
    echo "- charts/values.yaml"
    CUSTOM_MODEL=${CR_CUSTOM_REGISTRY_URL}/${CR_NAMESPACE}/$CUSTOM_WATSON_NLP_IMAGE_NAME:$CUSTOM_TAG
    echo "Set values:"
    echo "- $CUSTOM_MODEL"
    echo "- $IBM_ENTITLEMENT_SECRET"

    sed "s+IBM_ENTITLEMENT_SECRET+$IBM_ENTITLEMENT_SECRET+g;s+CUSTOM_MODEL+$CUSTOM_MODEL+g;" $(pwd)/charts/$HELM_RELEASE_NAME/values.yaml_template > $(pwd)/charts/$HELM_RELEASE_NAME/values.yaml
    cat $(pwd)/charts/$HELM_RELEASE_NAME/values.yaml
}

function installHelmChart () {

    echo ""
    echo "*********************"
    echo "installHelmChart"
    echo "*********************"
    echo ""

    TEMP_PATH_ROOT=$(pwd)
    cd $TEMP_PATH_ROOT/charts
    
    helm dependency update ./$HELM_RELEASE_NAME/
    helm install --dry-run --debug helm-test

    helm lint ./$HELM_RELEASE_NAME
    helm install $HELM_RELEASE_NAME ./$HELM_RELEASE_NAME

    verifyDeploment
    verifyPod
        
    cd $TEMP_PATH_ROOT
}

function verifyWatsonNLPContainer () {
    
    echo ""
    echo "*********************"
    echo "verifyWatsonNLPContainer"
    echo "*********************"
    echo ""

    export FIND=$WATSON_NLP_CONTAINER
    POD=$(kubectl get pods -n $DEFAULT_NAMESPACE | grep $FIND | awk '{print $1;}')
    echo "Pod: $POD"
    RESULT=$(kubectl exec --stdin --tty $POD --container $FIND -- curl -X POST 'http://localhost:8080/v1/watson.runtime.nlp.v1/NlpService/ClassificationPredict' -H 'accept: application/json' -H 'grpc-metadata-mm-model-id: ensemble_model' -H 'content-type: application/json' -d '{"rawDocument": { "text": "The credit card does not work, and I look at the savings, but I need more money to spend." }}')    
    echo ""
    echo "Result of the Watson NLP API request:"
    echo "http://localhost:8080/v1/watson.runtime.nlp.v1/NlpService/ClassificationPredict"
    echo ""
    echo "$RESULT"
    echo ""
    echo "Verify the running pod on your cluster."
    kubectl get pods -n $DEFAULT_NAMESPACE
    echo "Verify in the deployment in the Kubernetes dashboard."
    echo ""
    open "https://cloud.ibm.com/kubernetes/clusters/$CLUSTER_ID/overview"
    echo ""
    echo "Press any key to move on:"
    read ANY_VALUE
}

function verifyWatsonNLPLoadbalancer () {

    echo ""
    echo "*********************"
    echo "verifyWatsonNLP_loadbalancer"
    echo "this could take up to 10 min"
    echo "*********************"
    echo ""

    verifyLoadbalancer

    SERVICE=watson-nlp-custom-vpc-nlb
    EXTERNAL_IP=$(kubectl get svc $SERVICE | grep  $SERVICE | awk '{print $4;}')
    echo "EXTERNAL_IP: $EXTERNAL_IP"
    echo "Verify invocation of Watson NLP API from the local machine:"
    curl -s -X POST "http://$EXTERNAL_IP:8080/v1/watson.runtime.nlp.v1/NlpService/ClassificationPredict" \
            -H "accept: application/json" \
            -H "grpc-metadata-mm-model-id: ensemble_model" \
            -H "content-type: application/json" \
            -d "{ \"rawDocument\": \
                { \"text\": \"The credit card doesn t work, and I look at the savings, but I need more money to spend.\" }}" | jq
}

function uninstallHelmChart () {

    echo ""
    echo "*********************"
    echo "uninstallHelmChart"
    echo "*********************"
    echo ""

    echo "Press any key to move on with UNINSTALL:"
    read ANY_VALUE

    helm uninstall $HELM_RELEASE_NAME
}

# ************ functions used internal **************


function verifyLoadbalancer () {

    echo ""
    echo "*********************"
    echo "verifyLoadbalancer"
    echo "*********************"
    echo ""

    export max_retrys=10
    j=0
    array=("watson-nlp-custom-vpc-nlb")
    export STATUS_SUCCESS=""
    for i in "${array[@]}"
        do
            echo ""
            echo "------------------------------------------------------------------------"
            echo "Check for $i: ($j) from max retrys ($max_retrys)"
            j=0
            export FIND=$i
            while :
            do      
            ((j++))
            STATUS_CHECK=$(kubectl get svc $FIND -n $DEFAULT_NAMESPACE | grep $FIND | awk '{print $4;}')
            echo "Status: $STATUS_CHECK"
            if ([ "$STATUS_CHECK" != "$STATUS_SUCCESS" ] && [ "$STATUS_CHECK" != "<pending>" ]); then
                    echo "$(date +'%F %H:%M:%S') Status: $FIND is created ($STATUS_CHECK)"
                    echo "------------------------------------------------------------------------"
                    break
                elif [[ $j -eq $max_retrys ]]; then
                    echo "$(date +'%F %H:%M:%S') Maybe a problem does exists!"
                    echo "------------------------------------------------------------------------"
                    exit 1              
                else
                    echo "$(date +'%F %H:%M:%S') Status: $FIND($STATUS_CHECK)"
                    echo "------------------------------------------------------------------------"
                fi
                sleep 60
            done
        done
}

function verifyDeploment () {

    echo ""
    echo "*********************"
    echo "verifyDeploment"
    echo "*********************"
    echo ""

    export max_retrys=4
    j=0
    array=($WATSON_NLP_CONTAINER)
    export STATUS_SUCCESS=$WATSON_NLP_CONTAINER
    for i in "${array[@]}"
        do
            echo ""
            echo "------------------------------------------------------------------------"
            echo "Check for ($i)"
            j=0
            export FIND=$i
            while :
            do      
            ((j++))
            echo "($j) from max retrys ($max_retrys)"
            STATUS_CHECK=$(kubectl get deployment $FIND -n $DEFAULT_NAMESPACE | grep $FIND | awk '{print $1;}')
            echo "Status: $STATUS_CHECK"
            if [ "$STATUS_CHECK" = "$STATUS_SUCCESS" ]; then
                    echo "$(date +'%F %H:%M:%S') Status: $FIND is created"
                    echo "------------------------------------------------------------------------"
                    break
                elif [[ $j -eq $max_retrys ]]; then
                    echo "$(date +'%F %H:%M:%S') Maybe a problem does exists!"
                    echo "------------------------------------------------------------------------"
                    exit 1              
                else
                    echo "$(date +'%F %H:%M:%S') Status: $FIND($STATUS_CHECK)"
                    echo "------------------------------------------------------------------------"
                fi
                sleep 10
            done
        done
}

function verifyPod () {

    echo ""
    echo "*********************"
    echo "verifyPod could take 10 min"
    echo "*********************"
    echo ""

    export max_retrys=10
    j=0
    array=($WATSON_NLP_CONTAINER)
    export STATUS_SUCCESS="1/1"
    for i in "${array[@]}"
        do
            echo ""
            echo "------------------------------------------------------------------------"
            echo "Check for ($i)"
            j=0
            export FIND=$i
            while :
            do     
            ((j++))
            echo "($j) from max retrys ($max_retrys)"
            STATUS_CHECK=$(kubectl get pods -n $DEFAULT_NAMESPACE | grep $FIND | awk '{print $2;}')
            echo "Status: $STATUS_CHECK"
            if [ "$STATUS_CHECK" = "$STATUS_SUCCESS" ]; then
                    echo "$(date +'%F %H:%M:%S') Status: $FIND is created"
                    echo "------------------------------------------------------------------------"
                    break
                elif [[ $j -eq $max_retrys ]]; then
                    echo "$(date +'%F %H:%M:%S') Maybe a problem does exists!"
                    echo "------------------------------------------------------------------------"
                    exit 1              
                else
                    echo "$(date +'%F %H:%M:%S') Status: $FIND($STATUS_CHECK)"
                    echo "------------------------------------------------------------------------"
                fi
                sleep 60
            done
        done
}


#**********************************************************************************
# Execution
# *********************************************************************************

loginIBMCloud

configureIBMCloudRegistry

uploadCustomImageToIBMCloudRegistry

createDockerCustomConfigFile

connectToCluster

installHelmChart

verifyWatsonNLPContainer

verifyWatsonNLPLoadbalancer

uninstallHelmChart
