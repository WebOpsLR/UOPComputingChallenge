variable "kube_config_path" {
  description = "Path to the kubeconfig file used to reach the cluster."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Kubeconfig context to use. minikube creates a 'minikube' context."
  type        = string
  default     = "minikube"
}

variable "release_name" {
  description = "Name of the Helm release."
  type        = string
  default     = "tetris"
}

variable "namespace" {
  description = "Kubernetes namespace to deploy into. Created if it does not exist."
  type        = string
  default     = "tetris"
}
