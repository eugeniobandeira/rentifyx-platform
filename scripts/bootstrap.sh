#!/bin/bash

set -euo pipefail

echo "Bootstrap skeleton: preparar ambiente Terraform"
echo "1) Verificar se os módulos existem: modules/network, modules/kafka, modules/api-gateway, modules/cognito, modules/observability"
echo "2) Ajustar variáveis em terraform.tfvars ou exportar variáveis de ambiente"
echo "3) Rodar 'terraform init' no diretório raiz"
echo "4) Rodar 'terraform plan' para validar a configuração"

echo "Este script não aplica recursos automaticamente. Complete os módulos antes de usar."
