# Helpers compartidos.
#
# Las politicas se evaluan con `conftest test --parser hcl2 --combine`, asi que
# `input` es una LISTA de {path, contents}: un elemento por archivo .tf. Sin
# --combine cada archivo se evaluaria por separado y una regla de modulo
# ("debe declarar outputs") fallaria en variables.tf, que obviamente no los tiene.
package lib

import rego.v1

# Nombres de todas las variables declaradas en el modulo.
variable_names contains name if {
	some f in input
	some name, _ in f.contents.variable
}

# Nombres de todos los outputs declarados.
output_names contains name if {
	some f in input
	some name, _ in f.contents.output
}

# Tipos de recurso presentes: {"aws_vpc", "aws_s3_bucket", ...}
resource_types contains type if {
	some f in input
	some type, _ in f.contents.resource
}

# Cada recurso como {type, name, cfg}. En hcl2, resource es
# tipo -> nombre -> [config], de ahi los tres niveles.
resources contains r if {
	some f in input
	some type, instances in f.contents.resource
	some name, blocks in instances
	some cfg in blocks
	r := {"type": type, "name": name, "cfg": cfg}
}

# El bloque terraform {} es una LISTA de objetos, no un objeto.
has_required_version if {
	some f in input
	some block in f.contents.terraform
	block.required_version
}
