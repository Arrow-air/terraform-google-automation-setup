locals {
  tf_account    = format("tf-%s-%s-%s-%s", var.owner, var.region, var.environment, var.project)
  tf_ro_account = format("tf-ro-%s-%s-%s-%s", var.owner, var.region, var.environment, var.project)

  ### Terraform State bucket settings ###
  default_state_bucket_role_condition = {
    expression = "resource.name.startsWith(\"projects/_/buckets/%BUCKETNAME%/objects/organization/\")"
    title      = "allow_read_organization_folder"
  }
  default_state_bucket_roles = {
    # Make sure at least the terraform SA created for this project is allowed to write to the terraform state bucket
    "roles/storage.admin" = {
      members   = { (module.terraform_sa.map[local.tf_account].email) = "serviceAccount" }
      condition = local.default_state_bucket_role_condition
    }
    # Make sure at least the terraform planner SA created for this project is allowed to read the terraform state bucket
    "roles/storage.legacyBucketReader" = {
      members   = { (module.terraform_sa.map[local.tf_ro_account].email) = "serviceAccount" }
      condition = local.default_state_bucket_role_condition
    }
    "roles/storage.legacyObjectReader" = {
      members   = { (module.terraform_sa.map[local.tf_ro_account].email) = "serviceAccount" }
      condition = local.default_state_bucket_role_condition
    }
  }
  state_bucket_roles = merge(
    local.default_state_bucket_roles,
    var.state_bucket_roles,
    {
      # Make sure we add the members to the default roles if they get overwritten by the project settings
      for role, role_settings in var.state_bucket_roles : role => {
        members   = merge(local.default_state_bucket_roles[role].members, role_settings.members)
        condition = try(role_settings.condition, {})
      } if can(local.default_state_bucket_roles[role])
    }
  )
}

# ==========================================
# Set up workload identity for GitHub SA
# ==========================================
resource "google_iam_workload_identity_pool_provider" "github_provider" {
  project                            = var.cicd_project_id
  workload_identity_pool_id          = "automation"
  workload_identity_pool_provider_id = format("github-%s", var.repo_name)
  attribute_condition                = format("assertion.repository == '%s/%s'", var.github_owner, var.repo_name)
  attribute_mapping = {
    "google.subject"                = "assertion.sub"
    "attribute.aud"                 = "assertion.aud"
    "attribute.actor"               = "assertion.actor"
    "attribute.repository_owner_id" = "assertion.repository_owner_id"
    "attribute.repository"          = "assertion.repository"
  }
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

module "identity_provider_sa" {
  source  = "owlot/service-account/google"
  version = "~> 0.2.1"

  project     = var.project
  environment = var.environment
  owner       = var.owner
  gcp_project = var.cicd_project_id

  service_accounts = {
    "github-actions" = {
      roles = {
        "iam.workloadIdentityUser" = {
          members = {
            "identity_pool" = {
              email = format("//iam.googleapis.com/projects/%s/locations/global/workloadIdentityPools/%s/attribute.repository/%s/%s", var.cicd_project_number, var.workload_identity_pool_name, var.github_owner, var.repo_name),
              type  = "principalSet"
            }
          }
        }
      }
    }
  }
}

# ==========================================
# Set up Terraform required Service Accounts
# ==========================================
module "terraform_sa" {
  source  = "owlot/service-account/google"
  version = "~> 0.2.1"

  project     = var.project
  environment = var.environment
  owner       = var.owner
  gcp_project = var.cicd_project_id

  service_accounts = {
    (local.tf_account) = {
      description = "Allow terraform deployments from automation into the specified project."
      roles = {
        "iam.serviceAccountTokenCreator" = {
          members = merge(
            {
              "github-actions" = {
                email = module.identity_provider_sa.map["github-actions"].email
                type  = "serviceAccount"
              }
            },
            try(var.deployer_token_creators, {})
          )
        }
      }
    }
    (local.tf_ro_account) = {
      description = "Allow terraform plan from automation into the specified project."
      roles = {
        "iam.serviceAccountTokenCreator" = {
          members = merge(
            {
              "github-actions" = {
                email = module.identity_provider_sa.map["github-actions"].email
                type  = "serviceAccount"
              }
            },
            try(var.planner_token_creators, {})
          )
        }
      }
    }
  }

  depends_on = [module.identity_provider_sa]
}

# ==========================================
# Create Storage bucket for Terraform state
# ==========================================
module "tfstate_bucket" {
  source  = "owlot/storage-bucket/google"
  version = "~> 0.1.0"

  prefix      = var.prefix
  owner       = var.owner
  project     = var.project
  environment = var.environment
  region      = var.region
  gcp_project = var.cicd_project_id

  buckets = {
    "tfstate" = {
      location      = var.region == "global" ? "EU" : upper(var.region)
      storage_class = "MULTI_REGIONAL"

      lifecycle_rules = {
        "delete" = {
          condition = {
            num_newer_versions = "7"
            age                = "7"
          }
          action = {
            type = "Delete"
          }
        }
      }
      roles = local.state_bucket_roles
    }
  }
}
