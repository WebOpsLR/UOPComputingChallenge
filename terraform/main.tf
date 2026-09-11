# Deploy the local tetris Helm chart to the cluster.
resource "helm_release" "tetris" {
  name             = var.release_name
  namespace        = var.namespace
  create_namespace = true

  # Path to the chart directory relative to this Terraform config.
  chart = "${path.module}/../helm/tetris"

  # Wait for the resources to become ready before marking apply complete.
  wait    = true
  timeout = 300
}
