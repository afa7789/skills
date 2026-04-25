# Como Testar os Skills

Após modificar qualquer SKILL.md, teste o pipeline completo:

## Teste Rápido

1. Crie um projeto de teste:
   ```bash
   cd /tmp
   cargo new test-todo-cli
   cd test-todo-cli
   ```

2. Rode o pipeline (prompt simples):
   ```
   Build a TODO CLI in Rust with add, list, done commands. Use SQLite.
   ```

3. Verifique manualmente:
   - [ ] Tasks criadas no dagRobin?
   - [ ] Builder implementou as features?
   - [ ] QA evaluator rodou?
   - [ ] Build compila?
   - [ ] Tests passam?

## Teste Completo (Complexo)

Use um projeto maior para testar o pipeline inteiro:
- Planner → Architect → Builder → QA Evaluator
- Build-Evaluate-Fix loop
- Sprint contracts

## Pontos de Verificação

| Componente | O que verificar |
|------------|------------------|
| architect | Cria PLAN.md |
| builder | Segue TDD, verification protocol |
| code-reviewer | Dá feedback estruturado |
| qa-evaluator | Produce QA_REPORT.md |
| orchestrator | Coordena todos os agentes |

## Dica

Teste mudanças em um skill por vez para isolar problemas.
