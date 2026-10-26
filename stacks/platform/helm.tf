# Cluster controllers, Argo CD, and the config that ties them to app1. Chart versions are pinned.

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "3.5.0"
  namespace  = "kube-system"

  values = [yamlencode({
    clusterName = local.cluster_name
    region      = local.region
    vpcId       = data.aws_eks_cluster.this.vpc_config[0].vpc_id
    serviceAccount = {
      name        = "aws-load-balancer-controller"
      annotations = { "eks.amazonaws.com/role-arn" = data.aws_iam_role.irsa["aws-load-balancer-controller"].arn }
    }
  })]
}

resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  chart      = "external-dns"
  version    = "1.23.0"
  namespace  = "kube-system"

  values = [yamlencode({
    provider      = { name = "aws" }
    sources       = ["ingress"]
    domainFilters = [local.domain]
    policy        = "sync"
    txtOwnerId    = local.cluster_name
    extraArgs     = ["--aws-zone-type=public"]
    serviceAccount = {
      name        = "external-dns"
      annotations = { "eks.amazonaws.com/role-arn" = data.aws_iam_role.irsa["external-dns"].arn }
    }
  })]
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "2.12.0"
  namespace        = "external-secrets"
  create_namespace = true

  values = [yamlencode({
    serviceAccount = {
      name        = "external-secrets"
      annotations = { "eks.amazonaws.com/role-arn" = data.aws_iam_role.irsa["external-secrets"].arn }
    }
  })]
}

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = "9.59.0"
  namespace  = "kube-system"

  values = [yamlencode({
    autoDiscovery = { clusterName = local.cluster_name }
    awsRegion     = local.region
    rbac = {
      serviceAccount = {
        name        = "cluster-autoscaler"
        annotations = { "eks.amazonaws.com/role-arn" = data.aws_iam_role.irsa["cluster-autoscaler"].arn }
      }
    }
  })]
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "10.10.3"
  namespace        = "argocd"
  create_namespace = true

  # No local admin password to leak. Operators use `argocd --core` with their EKS access.
  values = [yamlencode({
    dex = { enabled = false }
    configs = {
      cm = { "admin.enabled" = false }
    }
  })]
}

# ClusterSecretStore, Argo CD repo credentials and the app1 Applications. A local chart so the
# custom resources are applied after the charts above have installed their CRDs.
# Secret stores, Argo CD repo credentials, and the root Application. A local chart so the custom
# resources are applied after the charts above have installed their CRDs.
# Secret stores, Argo CD repo credentials, and the root Application. A local chart so the custom
# resources are applied after the charts above have installed their CRDs.
resource "helm_release" "platform_config" {
  name      = "platform-config"
  chart     = "${path.module}/charts/platform-config"
  namespace = "argocd"

  values = [yamlencode({
    region = local.region
    # The master secret is read from the primary region; the repo key from this region.
    secretStoreRegions = distinct([local.region, local.primary_region])
    repo = {
      url        = local.repo_ssh_url
      secretName = local.repo_ssh_secret_name
    }
    root = {
      path = "apps/argocd"
      # Which version of each app runs here. The app pipelines update these files.
      valueFiles = [for app in keys(local.apps) : "$values/${local.environment}/${local.region}/${app}/values.yaml"]
      # What each app needs in this region. Both apps use the shared chart.
      values = {
        repoURL = local.repo_ssh_url
        apps = {
          for app, name in local.apps : app => {
            path = "apps/chart"
            values = {
              name     = name
              replicas = var.config.apps.replicas
              # Same path in every region: replicated from the primary region.
              image = { repository = "${local.account_id}.dkr.ecr.${local.region}.amazonaws.com/app1/${app}" }
              host  = "${app}.${local.domain}"
              # Every region serves the same hostname; Route53 latency routing picks one.
              dns = { setIdentifier = local.region, region = local.region }
              database = {
                host        = data.aws_db_instance.app[app].address
                port        = data.aws_db_instance.app[app].port
                name        = data.aws_db_instance.primary.db_name
                secretArn   = data.aws_db_instance.primary.master_user_secret[0].secret_arn
                secretStore = "aws-secrets-manager-${local.primary_region}"
              }
            }
          }
        }
      }
    }
  })]

  depends_on = [
    helm_release.argocd,
    helm_release.external_secrets,
    helm_release.aws_load_balancer_controller,
    helm_release.external_dns,
    aws_acm_certificate_validation.apps,
  ]
}
