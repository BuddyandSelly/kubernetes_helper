if [ ! -z "$KB_AUTH_TOKEN" ]
then
  AUTH_PATH="$SCRIPT_DIR/k8s-auth-token.json"
  rm -f -- $AUTH_PATH
  echo $KB_AUTH_TOKEN >> $AUTH_PATH

  ## ***** GOOGLE CONNECTOR
  # Download and install Google Cloud SDK
  if [ -z "$(which gcloud)" ]; then
    export CLOUDSDK_CORE_DISABLE_PROMPTS=1; curl https://sdk.cloud.google.com | bash && source /home/runner/google-cloud-sdk/path.bash.inc &&  gcloud --quiet components update kubectl
  fi

  # Connect to cluster
  export USE_GKE_GCLOUD_AUTH_PLUGIN=True
  gcloud components install gke-gcloud-auth-plugin
  gcloud auth activate-service-account --key-file $AUTH_PATH --project $PROJECT_NAME
  # The registry host is the first segment of the image name, not "$CLUSTER_REGION-docker.pkg.dev":
  # cluster_region carries a GKE zone (europe-west4-a) because get-credentials needs one, and
  # europe-west4-a-docker.pkg.dev is not a registry, so configure-docker answered "not a supported
  # registry" and registered no credential helper at all. Taking the host from image_name gives the
  # real one for Artifact Registry (europe-west4-docker.pkg.dev) and for the legacy gcr.io hosts.
  gcloud auth configure-docker "${IMAGE_NAME%%/*}" --quiet
  gcloud container clusters get-credentials $CLUSTER_NAME --region $CLUSTER_REGION

  ## ***** END GOOGLE CONNECTOR
fi

# Nothing is built or pushed here. CI builds the image and pushes it to Artifact Registry before
# calling this script, and the deploy below only points the cluster at that tag. The build and push
# this file used to carry were commented out when GAR support landed; the "gcloud docker
# --authorize-only" call that went with them is gone too, since it only handed out short-lived
# access for the gcr.io hosts that no image uses any more.
