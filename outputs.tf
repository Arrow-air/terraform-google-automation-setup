output "github_actions_account" {
  value = {
    email      = module.identity_provider_sa.map["github-actions"].email
    id         = module.identity_provider_sa.map["github-actions"].id
    account_id = module.identity_provider_sa.map["github-actions"].account_id
  }
}
output "tf_account" {
  value = {
    email      = module.terraform_sa.map[local.tf_account].email
    id         = module.terraform_sa.map[local.tf_account].id
    account_id = module.terraform_sa.map[local.tf_account].account_id
  }
}
output "tf_ro_account" {
  value = {
    email      = module.terraform_sa.map[local.tf_ro_account].email
    id         = module.terraform_sa.map[local.tf_ro_account].id
    account_id = module.terraform_sa.map[local.tf_ro_account].account_id
  }
}
output "tf_state_bucket" {
  value = {
    self_link = module.tfstate_bucket.map["tfstate"].self_link
    url       = module.tfstate_bucket.map["tfstate"].url
    name      = module.tfstate_bucket.map["tfstate"].name
    id        = module.tfstate_bucket.map["tfstate"].id
  }
}
