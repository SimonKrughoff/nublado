resource "kubernetes_namespace" "ingress_nginx" {
  metadata {
    name = "ingress-nginx"

    labels {
      name = "ingress-nginx"
    }
  }
}

resource "kubernetes_config_map" "tcp_services" {
  metadata {
    name      = "tcp-services"
    namespace = "ingress-nginx"
  }

  depends_on = ["kubernetes_namespace.ingress_nginx"]
}

resource "kubernetes_config_map" "udp_services" {
  metadata {
    name      = "udp-services"
    namespace = "ingress-nginx"
  }

  depends_on = ["kubernetes_namespace.ingress_nginx"]
}

resource "kubernetes_service_account" "nginx_ingress" {
  metadata {
    name      = "nginx-ingress-serviceaccount"
    namespace = "ingress-nginx"
  }

  depends_on = ["kubernetes_namespace.ingress_nginx"]
}

resource "kubernetes_cluster_role" "nginx_ingress" {
  metadata {
    name = "nginx-ingress-clusterrole"
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps", "endpoints", "nodes", "pods", "secrets"]
    verbs      = ["list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["get"]
  }

  rule {
    api_groups = [""]
    resources  = ["services"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["extensions"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["create", "patch"]
  }

  rule {
    api_groups = ["extensions"]
    resources  = ["ingresses/status"]
    verbs      = ["update"]
  }
}

resource "kubernetes_config_map" "nginx_configuration" {
  metadata {
    name      = "nginx-configuration"
    namespace = "ingress-nginx"
  }

  depends_on = ["kubernetes_namespace.ingress_nginx"]
}

resource "kubernetes_role" "nginx_ingress" {
  metadata {
    name      = "nginx-ingress-role"
    namespace = "ingress-nginx"
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps", "pods", "secrets", "namespaces"]
    verbs      = ["get"]
  }

  rule {
    api_groups     = [""]
    resources      = ["configmaps"]
    resource_names = ["ingress-controller-leader-nginx"]
    verbs          = ["get", "update"]
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["create"]
  }

  rule {
    api_groups = [""]
    resources  = ["endpoints"]
    verbs      = ["get"]
  }

  depends_on = ["kubernetes_namespace.ingress_nginx"]
}

resource "kubernetes_role_binding" "nginx_ingress" {
  metadata {
    name      = "nginx-ingress-role"
    namespace = "ingress-nginx"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = "nginx-ingress-role"
  }

  subject = {
    kind      = "ServiceAccount"
    name      = "nginx-ingress-serviceaccount"
    namespace = "ingress-nginx"
  }

  depends_on = [
    "kubernetes_namespace.ingress_nginx",
    "kubernetes_service_account.nginx_ingress",
  ]
}

resource "kubernetes_cluster_role_binding" "nginx_ingress" {
  metadata {
    name = "nginx-ingress-role"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "nginx-ingress-clusterrole"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "nginx-ingress-serviceaccount"
    namespace = "ingress-nginx"
  }

  depends_on = [
    "kubernetes_service_account.nginx_ingress",
  ]
}

resource "kubernetes_deployment" "nginx_ingress_controller" {
  metadata {
    name      = "nginx-ingress-controller"
    namespace = "ingress-nginx"
  }

  depends_on = ["kubernetes_namespace.ingress_nginx"]

  spec {
    selector {
      app = "ingress-nginx"
    }

    template {
      metadata {
        labels {
          app = "ingress-nginx"
        }

        annotations {
          "prometheus.io/port"   = "10254"
          "prometheus.io/scrape" = "true"
        }
      }

      spec {
        service_account_name = "nginx-ingress-serviceaccount"

        container {
          name  = "nginx-ingress-controller"
          image = "quay.io/kubernetes-ingress-controller/nginx-ingress-controller:0.21.0"

          args = [
            "/nginx-ingress-controller",
            "--configmap=$$(POD_NAMESPACE)/nginx-configuration",
            "--tcp-services-configmap=$$(POD_NAMESPACE)/tcp-services",
            "--udp-services-configmap=$$(POD_NAMESPACE)/udp-services",
            "--publish-service=$$(POD_NAMESPACE)/ingress-nginx",
            "--annotations-prefix=nginx.ingress.kubernetes.io",
          ]

          security_context {
            capabilities {
              drop = ["ALL"]
              add  = ["NET_BIND_SERVICE"]
            }

            run_as_user = 33
          }

          env {
            name = "POD_NAME"

            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }

          env {
            name = "POD_NAMESPACE"

            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }

          port {
            name           = "http"
            container_port = 80
          }

          port {
            name           = "https"
            container_port = 443
          }

          liveness_probe {
            failure_threshold = 3

            http_get {
              path   = "/healthz"
              port   = 10254
              scheme = "HTTP"
            }

            initial_delay_seconds = 10
            period_seconds        = 10
            success_threshold     = 1
            timeout_seconds       = 1
          }

          readiness_probe {
            failure_threshold = 3

            http_get {
              path   = "/healthz"
              port   = 10254
              scheme = "HTTP"
            }

            period_seconds    = 10
            success_threshold = 1
            timeout_seconds   = 1
          }
        }
      }
    }
  }

  depends_on = [
    "kubernetes_namespace.ingress_nginx",
    "kubernetes_service_account.nginx_ingress",
  ]
}
