output "role_arn" {
  description = "Ponlo en el repositorio como variable AWS_DEPLOY_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}

output "comando_gh" {
  description = "Configura la variable de golpe con la CLI de GitHub"
  value       = "gh variable set AWS_DEPLOY_ROLE_ARN --body ${aws_iam_role.github_actions.arn}"
}

output "confianza" {
  description = "Unico sujeto que puede asumir el rol"
  value       = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/${var.github_branch}"
}

output "oidc_provider_arn" {
  description = "Proveedor OIDC en uso, se haya creado aqui o viniera dado"
  value       = local.provider_arn
}

output "proveedor_creado" {
  description = "false => se reutilizo uno que ya existia en la cuenta"
  value       = local.create_provider
}
