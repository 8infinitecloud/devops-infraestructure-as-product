#!/usr/bin/env bash
#
# Despliega un hands-on del taller en la cuenta de AWS que tengas configurada.
#
#   ./scripts/bootstrap.sh            # desplegar
#   ./scripts/bootstrap.sh plan       # solo ver que haria
#   ./scripts/bootstrap.sh destroy    # desmontar
#
# Pensado para AWS CloudShell, donde las credenciales ya estan puestas y no hace
# falta configurar nada. Funciona igual en macOS y en Linux.
#
# Lo que hace, en orden:
#   1. Comprueba que estan las herramientas; instala las que falten en ~/.local/bin
#   2. Comprueba que hay credenciales de AWS
#   3. `make bin` — empaqueta las Lambdas. SIEMPRE antes del plan: Terraform no
#      compila nada, archive_file lee build/ en tiempo de plan.
#   4. Verifica la ARQUITECTURA del binario Go. Es el fallo que mas cuesta
#      diagnosticar: en un Mac con Apple Silicon, un GOARCH mal puesto produce un
#      binario ARM que Terraform sube tan feliz y que revienta en ejecucion.
#   5. terraform init + apply
#
set -euo pipefail

# --- Ajustes -----------------------------------------------------------------

TF_VERSION="${TF_VERSION:-1.5.7}"   # la misma que usa la pipeline
LOCAL_BIN="${HOME}/.local/bin"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Se acepta un "01" delante por compatibilidad con instrucciones antiguas.
[ "${1:-}" = "01" ] && shift
ACTION="${1:-apply}"

# --- Presentacion ------------------------------------------------------------

if [ -t 1 ]; then
  ROJO=$'\033[31m'; VERDE=$'\033[32m'; AMBAR=$'\033[33m'; NEGRITA=$'\033[1m'; FIN=$'\033[0m'
else
  ROJO=""; VERDE=""; AMBAR=""; NEGRITA=""; FIN=""
fi

paso()  { printf '\n%s==> %s%s\n' "${NEGRITA}" "$*" "${FIN}"; }
ok()    { printf '    %s✓%s %s\n' "${VERDE}" "${FIN}" "$*"; }
aviso() { printf '    %s!%s %s\n' "${AMBAR}" "${FIN}" "$*"; }
fatal() { printf '\n%sERROR:%s %s\n\n' "${ROJO}" "${FIN}" "$*" >&2; exit 1; }

# --- Argumentos --------------------------------------------------------------

DIR="hands-on/01-terraform-os"
BUILD_DIR="${DIR}/modules/engine/lambda-functions"
NOMBRE="Catalogo de infraestructura sobre AWS Service Catalog"

case "${ACTION}" in
  apply|plan|destroy) ;;
  *) cat >&2 <<EOF
Uso: $0 [apply|plan|destroy]

  apply     Despliega el motor, el catalogo y la pipeline  (por defecto)
  plan      Solo muestra que se crearia
  destroy   Desmonta. Termina antes los productos aprovisionados
EOF
     exit 2 ;;
esac

printf '\n%s%s%s\n' "${NEGRITA}" "${NOMBRE}  [${ACTION}]" "${FIN}"

# --- 1. Herramientas ---------------------------------------------------------

paso "Comprobando herramientas"
mkdir -p "${LOCAL_BIN}"
export PATH="${LOCAL_BIN}:${PATH}"

so="$(uname -s)"; arq="$(uname -m)"
case "${arq}" in
  x86_64|amd64) arq_tf="amd64"; arq_go="amd64" ;;
  arm64|aarch64) arq_tf="arm64"; arq_go="arm64" ;;
  *) fatal "Arquitectura no soportada: ${arq}" ;;
esac
case "${so}" in
  Linux)  so_tf="linux";  so_go="linux"  ;;
  Darwin) so_tf="darwin"; so_go="darwin" ;;
  *) fatal "Sistema no soportado: ${so}. Usa Linux, macOS o AWS CloudShell." ;;
esac

# Paquetes de sistema que no merece la pena instalar a mano.
faltan_sistema=""
for t in make rsync unzip curl git; do
  command -v "$t" >/dev/null 2>&1 || faltan_sistema="${faltan_sistema} $t"
done
if [ -n "${faltan_sistema}" ]; then
  aviso "Faltan:${faltan_sistema}"
  if command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y ${faltan_sistema} >/dev/null && ok "instalados con dnf"
  elif command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -qq && sudo apt-get install -y -qq ${faltan_sistema} >/dev/null && ok "instalados con apt"
  else
    fatal "Instala a mano:${faltan_sistema}"
  fi
fi

command -v python3 >/dev/null 2>&1 || fatal "Falta python3. Instalalo antes de seguir."
python3 -m pip --version >/dev/null 2>&1 || fatal "Falta pip. Prueba: python3 -m ensurepip --upgrade"
ok "python3 $(python3 -c 'import sys;print(".".join(map(str,sys.version_info[:3])))')"

# Terraform: version FIJADA, la misma que la pipeline. Si `fmt -check` da
# veredictos distintos aqui y en CodeBuild, el problema es siempre la version.
if ! command -v terraform >/dev/null 2>&1; then
  aviso "Terraform no esta, instalando ${TF_VERSION} en ${LOCAL_BIN}"
  tmp="$(mktemp -d)"
  curl -fsSL -o "${tmp}/tf.zip" \
    "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_${so_tf}_${arq_tf}.zip"
  unzip -oq "${tmp}/tf.zip" -d "${LOCAL_BIN}"
  rm -rf "${tmp}"
fi
ok "terraform $(terraform version -json 2>/dev/null | grep -o '"terraform_version":"[^"]*"' | cut -d'"' -f4 || terraform version | head -1)"

# Go: la version sale del go.mod del modulo, no se fija aqui.
go_necesario="$(awk '/^go /{print $2; exit}' "${REPO_ROOT}/${BUILD_DIR}/go.mod" 2>/dev/null \
  || awk '/^go /{print $2; exit}' "${REPO_ROOT}/${BUILD_DIR}/terraform_open_source_parameter_parser/go.mod")"
if ! command -v go >/dev/null 2>&1; then
  aviso "Go no esta, instalando ${go_necesario} en ${LOCAL_BIN}/../go"
  tmp="$(mktemp -d)"
  curl -fsSL -o "${tmp}/go.tgz" "https://go.dev/dl/go${go_necesario}.${so_go}-${arq_go}.tar.gz" \
    || fatal "No pude descargar Go ${go_necesario}. Instalalo a mano: https://go.dev/dl/"
  rm -rf "${HOME}/.local/go"
  mkdir -p "${HOME}/.local"
  tar -xzf "${tmp}/go.tgz" -C "${HOME}/.local"
  ln -sf "${HOME}/.local/go/bin/go" "${LOCAL_BIN}/go"
  rm -rf "${tmp}"
fi
ok "go $(go version | awk '{print $3}')"

# --- 2. Credenciales ---------------------------------------------------------

paso "Comprobando credenciales de AWS"
command -v aws >/dev/null 2>&1 || fatal "Falta la AWS CLI. En CloudShell ya viene."
identidad="$(aws sts get-caller-identity --output json 2>/dev/null)" \
  || fatal "Sin credenciales de AWS validas. Ejecuta 'aws configure' o abre AWS CloudShell."
cuenta="$(printf '%s' "${identidad}" | grep -o '"Account": *"[^"]*"' | cut -d'"' -f4)"
quien="$(printf '%s' "${identidad}"  | grep -o '"Arn": *"[^"]*"'     | cut -d'"' -f4)"
region="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null || echo us-east-1)}}"
export AWS_REGION="${region}" AWS_DEFAULT_REGION="${region}"
ok "cuenta ${cuenta}, region ${region}"
ok "${quien}"


# --- 3. Configuracion --------------------------------------------------------

paso "Comprobando la configuracion"
cd "${REPO_ROOT}/${DIR}"
if [ ! -f terraform.tfvars ]; then
  if [ -n "${TF_VAR_github_repository_id:-}" ]; then
    ok "sin terraform.tfvars, usando las variables TF_VAR_* del entorno"
  else
    cp terraform.tfvars.example terraform.tfvars
    fatal "He creado ${DIR}/terraform.tfvars a partir del ejemplo.
       RELLENALO y vuelve a lanzar el script. Como minimo necesitas
       github_repository_id .

       Alternativa sin fichero:
         export TF_VAR_github_repository_id=\"mi-org/mi-repo\""
  fi
else
  ok "terraform.tfvars presente"
fi

# --- 4. Empaquetado de las Lambdas -------------------------------------------

if [ "${ACTION}" != "destroy" ]; then
  paso "Empaquetando las Lambdas (make bin)"
  ( cd "${REPO_ROOT}/${BUILD_DIR}" && make bin )

  # El chequeo que evita el fallo caro: un binario ARM subido a una Lambda que
  # declara x86_64 despliega sin quejarse y falla al invocarse.
    ( cd "${REPO_ROOT}/${BUILD_DIR}" && make verify )
  ok "artefactos listos"
fi

# --- 5. Terraform ------------------------------------------------------------

paso "terraform init"
terraform init -input=false -no-color

case "${ACTION}" in
  plan)
    paso "terraform plan"
    terraform plan -input=false -no-color
    exit 0 ;;
  destroy)
    paso "terraform destroy"
    cat <<EOF

${AMBAR}ANTES de seguir:${FIN} termina los productos APROVISIONADOS desde Service Catalog.
Si destruyes el motor primero, no queda nada capaz de ejecutar su destroy y los
recursos se quedan huerfanos en la cuenta.

    aws servicecatalog terminate-provisioned-product --provisioned-product-id <pp-...>

EOF
    read -r -p "¿Los has terminado ya? [escribe 'si' para continuar] " r
    [ "${r}" = "si" ] || fatal "Cancelado. Termina los productos y vuelve."
    terraform destroy -input=false -no-color
    exit 0 ;;
esac

paso "terraform apply"
terraform apply -input=false -auto-approve -no-color

# --- 6. Que queda por hacer a mano -------------------------------------------

paso "Desplegado"
terraform output -no-color 2>/dev/null || true

necesita_auth="$(terraform output -raw connection_needs_authorization 2>/dev/null || echo false)"
if [ "${necesita_auth}" = "true" ]; then
  cat <<EOF

${AMBAR}${NEGRITA}FALTA UN PASO MANUAL, y no se puede automatizar.${FIN}

La conexion a GitHub nace en estado PENDING: el handshake OAuth no tiene API.
Hasta que la autorices, la pipeline no puede leer del repositorio.

  1. Consola de AWS -> CodePipeline -> Settings -> Connections
  2. Selecciona la conexion pendiente -> "Update pending connection"
  3. Autoriza la app "AWS Connector for GitHub"

     https://${region}.console.aws.amazon.com/codesuite/settings/connections?region=${region}

Despues, un push a la rama configurada dispara la pipeline.
EOF
else
  printf '\n    La conexion a GitHub ya estaba autorizada: no queda nada manual.\n'
fi

printf '\n%sListo.%s\n\n' "${VERDE}${NEGRITA}" "${FIN}"
