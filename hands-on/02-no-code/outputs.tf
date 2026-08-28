output "proyecto" {
  description = "Proyecto que agrupa los workspaces del catalogo"
  value       = tfe_project.catalogo.name
}

output "workspace_demo" {
  description = "Workspace de demostracion, con Health activado"
  value       = { for k, w in tfe_workspace.demo : k => w.name }
}

output "run_tasks" {
  description = "Run tasks configurados, con su nivel de exigencia y etapa"
  value = length(var.run_tasks) == 0 ? { "(ninguno)" = "define var.run_tasks para enchufar Infracost, Snyk u otro" } : {
    for k, t in var.run_tasks : k => "${t.enforcement_level} en ${join(", ", t.stages)}"
  }
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
