output "release_name" {
  description = "The deployed Helm release name."
  value       = helm_release.tetris.name
}

output "namespace" {
  description = "Namespace the app was deployed into."
  value       = helm_release.tetris.namespace
}

output "access_command" {
  description = "Command to open the app in a browser via minikube."
  value       = "minikube service ${var.release_name}-tetris -n ${var.namespace}"
}
