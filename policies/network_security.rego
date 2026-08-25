# Reglas de red y almacenamiento. Complementan a Checkov: aqui van las
# decisiones de Aurex, no las misconfiguraciones genericas que Checkov ya cubre.
package main

import data.lib
import rego.v1

# --- Exposicion a internet -------------------------------------------------

deny contains msg if {
	some r in lib.resources
	r.type == "aws_security_group"
	some rule in r.cfg.ingress
	"0.0.0.0/0" in rule.cidr_blocks
	msg := sprintf("aws_security_group.%s abre ingress a 0.0.0.0/0. Acota el origen.", [r.name])
}

deny contains msg if {
	some r in lib.resources
	r.type == "aws_security_group_rule"
	r.cfg.type == "ingress"
	"0.0.0.0/0" in r.cfg.cidr_blocks
	msg := sprintf("aws_security_group_rule.%s abre ingress a 0.0.0.0/0. Acota el origen.", [r.name])
}

# --- Almacenamiento --------------------------------------------------------

deny contains msg if {
	"aws_s3_bucket" in lib.resource_types
	not "aws_s3_bucket_public_access_block" in lib.resource_types
	msg := "Hay un aws_s3_bucket sin aws_s3_bucket_public_access_block. Es el fallo mas caro y mas comun."
}

deny contains msg if {
	"aws_s3_bucket" in lib.resource_types
	not "aws_s3_bucket_server_side_encryption_configuration" in lib.resource_types
	msg := "Hay un aws_s3_bucket sin cifrado en reposo declarado."
}

# --- Permisos --------------------------------------------------------------

warn contains msg if {
	some r in lib.resources
	r.type == "aws_iam_role_policy"
	contains(r.cfg.policy, "\"Action\":\"*\"")
	msg := sprintf("aws_iam_role_policy.%s concede Action:*. Acota los permisos.", [r.name])
}
