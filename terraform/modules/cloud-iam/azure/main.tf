locals {
  k8s_sa_name   = coalesce(var.k8s_sa_name, var.service_name)
  identity_name = "${var.service_name}-${var.environment}"
}

data "azurerm_client_config" "current" {}

# --- User-assigned Managed Identity ------------------------------------------

resource "azurerm_user_assigned_identity" "this" {
  name                = local.identity_name
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = {
    managed-by  = "terraform"
    service     = var.service_name
    environment = var.environment
    namespace   = var.namespace
  }
}

# --- Federated identity credential -------------------------------------------
# Binds the AKS-issued token for the Kubernetes ServiceAccount to this MI.

resource "azurerm_federated_identity_credential" "k8s_sa" {
  name                = "${local.identity_name}-k8s"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.this.id

  issuer  = var.aks_oidc_issuer_url
  subject = "system:serviceaccount:${var.namespace}:${local.k8s_sa_name}"

  # azure.workload.identity/client-id is the only supported audience for AKS WI.
  audiences = ["api://AzureADTokenExchange"]
}

# --- Role assignments ---------------------------------------------------------

resource "azurerm_role_assignment" "this" {
  for_each = {
    for idx, ra in var.role_assignments : "${ra.role_definition_name}-${idx}" => ra
  }

  scope                = each.value.scope
  role_definition_name = each.value.role_definition_name
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}
