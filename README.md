# Computing Challenge

Read the [guide](https://webopslr.github.io) for instructions on how to complete the challenge

## Contents

In this challenge, users will host their own minikube cluster then use Terraform and Helm to deploy to it. This is a a basic setup to give an introduction to Infrastructure as Code and Configuration as Code in the context of working with Kubernetes.

## Files you need to edit

You choose which Docker image to deploy. Before running `terraform apply`, fill
in your own values in the two files below. Every value you need to change is
marked with a `# TODO:` comment; replace the placeholder value next to it.

Pick an image first. [Docker Hub](https://hub.docker.com/) has thousands of free
images. Note the image name, its tag, and the port it listens on (shown on the
image's Docker Hub page), you'll need all three below.

1. **`helm/challenge/values.yaml`** sets the image to deploy and its ports:
   - `image.repository` is the image name (e.g. `nginxdemos/hello`).
   - `image.tag` is the image tag (e.g. `latest`).
   - `containerPort` is the port the image listens on inside the container.
   - `service.port` is usually the same as `containerPort`.
   - `service.nodePort` is the port on your machine, a number in the
     30000-32767 range.

2. **`terraform/terraform.tfvars`** sets your deployment name and namespace:
   - `release_name` is a name for your deployment.
   - `namespace` is the Kubernetes namespace to deploy into.

### Worked example

Say you chose the image `nginxdemos/hello`, which listens on port `80`:

```yaml
# helm/challenge/values.yaml
image:
  repository: nginxdemos/hello
  tag: latest
  pullPolicy: IfNotPresent
containerPort: 80
service:
  type: NodePort
  port: 80
  nodePort: 30080
```

```hcl
# terraform/terraform.tfvars
release_name = "hello"
namespace    = "hello"
```

With those filled in, `terraform apply` will deploy your chosen image.

See the full [guide](https://webopslr.github.io) for the complete walkthrough.
