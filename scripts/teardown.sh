#!/bin/bash

set -euo pipefail

echo "Teardown skeleton: remover dependências antes de destruir infraestrutura"
echo "1) Excluir Ingress/Kubernetes no cluster antes de destruir o Terraform"
echo "2) Confirmar que nenhum ALB permanece ativo"
echo "3) Rodar 'terraform destroy' apenas depois que o ambiente estiver limpo"

echo "Este script não destrói nada automaticamente. Complete o processo manualmente conforme o plano."
