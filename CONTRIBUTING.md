# Como contribuir

A interface e a documentação usam português brasileiro. Abra uma issue com o problema ou envie um pull request com uma mudança focada e instruções para verificar o resultado.

## Preparar o ambiente

Siga o [README](README.md) para instalar Flutter 3.47.7 / Dart 3.13.5 e as ferramentas da plataforma. Preserve os arquivos de lock; atualizações de dependências devem explicar o motivo e repetir as verificações afetadas.

Antes de enviar uma alteração:

```powershell
cd app
flutter pub get
flutter analyze
cd ..\packages\validation
flutter pub get
flutter test --reporter expanded
```

Para alterações no motor, instale explicitamente os modelos e execute `python -m pytest ml/tests -q` na venv, a partir da raiz. Mudanças em seleção, renderização ou salvamento também precisam das integrações da plataforma afetada. O README explica a execução dos alvos Windows.

## Regras importantes

- Não enviar PDFs pessoais, bancos de anotações, credenciais, SDKs, modelos ou executáveis compilados.
- Não usar IA remota nem baixar modelos no caminho de inferência. Downloads exigem ação explícita.
- Preservar o isolamento do modo A: ele não pode carregar ou invocar o encoder.
- Compartilhar tradução e candidatos ao comparar A/B; não interpretar cosseno como probabilidade.
- Não usar respostas esperadas da avaliação na inferência nem ajustar os rótulos para melhorar os resultados medidos.
- Proteger edições manuais e detectar conflitos ao salvar o original. A exportação de cópia deve preservar o arquivo de origem.
- Usar documentos sintéticos e banco isolado nos testes. Informar exatamente quais plataformas e aparelhos foram executados.
- Atualizar `IMPLEMENTATION_PLAN.md` e `docs/TESTES_E_RESULTADOS.md` com as evidências e limitações relevantes.

Ao relatar um defeito, inclua sistema, versão do app/Flutter, modo usado, passos, resultado esperado e erro completo. Só compartilhe um PDF ou captura se você puder torná-lo público; prefira uma reprodução sintética.

O GitHub Actions verifica análise e testes Dart compartilhados. Os workflows iOS no Codemagic são manuais e dependem da configuração da conta; assinatura Apple e chaves nunca devem ir para o Git.
