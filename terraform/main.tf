# Deploy your Docker image as a Helm chart to the cluster.
resource "helm_release" "app" {
  name             = var.release_name
  namespace        = var.namespace
  create_namespace = true

  # Path to the chart directory relative to this Terraform config.
  chart = "${path.module}/../helm/challenge"

  # Wait for the resources to become ready before marking apply complete.
  wait    = true
  timeout = 300

  # Roll back / clean up the release automatically if the apply fails, so a
  # failed run does not leave a stuck "pending-install" release behind (which
  # otherwise causes: "cannot re-use a name that is still in use").
  atomic          = true
  cleanup_on_fail = true
}
