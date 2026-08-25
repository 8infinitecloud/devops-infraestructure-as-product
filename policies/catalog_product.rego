# Reglas que debe cumplir cualquier modulo para entrar al catalogo de Aurex.
package main

import data.lib
import rego.v1

# --- Atribucion de coste --------------------------------------------------
# Sin centro de coste no hay forma de imputar lo que el catalogo despliega.

deny contains msg if {
	count(lib.variable_names) == 0
	msg := "El modulo no declara ninguna variable. Un producto del catalogo debe ser parametrizable."
}

deny contains msg if {
	count(lib.variable_names) > 0
	not "cost_center" in lib.variable_names
	msg := "Falta la variable 'cost_center'. Es obligatoria para imputar el gasto del producto."
}

deny contains msg if {
	count(lib.variable_names) > 0
	not "environment_name" in lib.variable_names
	msg := "Falta la variable 'environment_name'. Prefija los recursos y evita colisiones entre despliegues."
}

# --- Contrato con Service Catalog -----------------------------------------
# Sin outputs, el producto aprovisionado no devuelve nada al usuario final.

deny contains msg if {
	count(lib.output_names) == 0
	msg := "El modulo no declara outputs. Service Catalog los muestra como record outputs del producto."
}

# --- Documentacion ---------------------------------------------------------
# El parameter parser expone description y default como ayuda en la consola.

warn contains msg if {
	some f in input
	some name, blocks in f.contents.variable
	some cfg in blocks
	not cfg.description
	msg := sprintf("La variable '%s' no tiene description. Es lo que ve el usuario final en Service Catalog.", [name])
}

# --- Reproducibilidad ------------------------------------------------------

warn contains msg if {
	not lib.has_required_version
	msg := "No se declara required_version. Fijala para que el aprovisionamiento sea reproducible."
}
