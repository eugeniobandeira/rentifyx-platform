# Estado do Projeto

## Decisões

- `prod` é o único ambiente inicial.
- A infraestrutura de estado remoto usa S3 + DynamoDB e não é destruída no ciclo de teardown.
- O projeto prioriza redução de custo em vez de alta disponibilidade total.

## Bloqueadores

- Nenhum bloqueador inicial definido.

## Pendências

- Criar `backend.tf` e configurar o backend remoto.
- Definir módulos Terraform em `modules/`.
- Implementar scripts de bootstrap e teardown.
- Configurar GitHub Actions para validar Terraform.
