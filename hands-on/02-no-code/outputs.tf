output "proyecto" {
  description = "Proyecto que agrupa los workspaces del catalogo"
  value       = tfe_project.catalogo.name
}

output "workspace_demo" {
  description = "Workspace de demostracion, con Health activado"
  value       = { for k, w in tfe_workspace.demo : k => w.name }
}

output "run_task_infracost" {
  description = "Estado del run task de Infracost"
  value = var.infracost_run_task_url != "" ? format(
    "configurado, %s, en post_plan", var.infracost_enforcement
  ) : "no configurado (falta infracost_run_task_url)"
}

output "siguiente_paso" {
  description = "Lo que hay que hacer a mano despues del apply"
  value       = <<-EOT
    1. Publica el modulo en el registro privado: Registry -> Publish -> Module
    2. Marcalo como no-code: Registry -> <modulo> -> Configure no-code provisioning
    3. Asignalo al proyecto '${tfe_project.catalogo.name}'
    4. En el workspace '${one([for w in tfe_workspace.demo : w.name])}': comprueba que
       Health esta activo (Settings -> Health) y lanza un run para ver el run task.
  EOT
}
