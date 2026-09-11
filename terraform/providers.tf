terraform {
  required_version = ">= 1.3.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

# The Helm provider talks to your cluster through your local kubeconfig.
# `minikube start` sets the current context to "minikube" automatically.
provider "helm" {
  kubernetes {
    config_path    = var.kube_config_path
    config_context = var.kube_context
  }
}
