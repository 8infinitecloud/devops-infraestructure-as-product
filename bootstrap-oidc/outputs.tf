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
