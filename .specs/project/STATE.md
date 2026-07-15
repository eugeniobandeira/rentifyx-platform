# Estado do Projeto

## Decisões

- `prod` é o único ambiente inicial.
- A infraestrutura de estado remoto usa S3 + DynamoDB e não é destruída no ciclo de teardown.
- O projeto prioriza redução de custo em vez de alta disponibilidade total.

## Bloqueadores

- **`prod/main.tf` está desconectado da raiz do repo.** Descoberto 2026-07-15 ao integrar `modules/kafka/`: `terraform init`/`validate` rodado na raiz não enxerga `prod/main.tf` (Terraform não desce em subdiretórios sozinho), e `prod/` não tem `providers.tf`/`backend.tf`/`versions.tf` próprios — então nada em `prod/main.tf` (todos os 6 módulos: network/eks/kafka/api-gateway/cognito/observability) é de fato aplicável hoje. Pré-existente, não introduzido pela feature Kafka — afeta todos os módulos igualmente. Precisa de uma correção estrutural (mover conteúdo de `prod/main.tf` pra um `main.tf` na raiz, ou fazer `prod/` ser seu próprio root module com cópia de provider/backend) antes de qualquer `terraform apply` real funcionar.

## Pendências

- Criar `backend.tf` e configurar o backend remoto.
- Definir módulos Terraform em `modules/`.
- Implementar scripts de bootstrap e teardown.
- Configurar GitHub Actions para validar Terraform.
