# Eko

## Eko 2.2

Fundo do ícone corrigido para cortiça, recortado como quadrado de cantos arredondados, sem moldura. O adesivo central foi preservado. Substitui o xadrez da versão 2.1.

## Eko 2.1

Ícone de colagem aprovado, com papel xadrez verde e contorno recortado transparente. O recurso EkoAppIcon.icns contém tamanhos de 16 a 1024 pixels e está integrado ao aplicativo e ao cabeçalho dos ajustes.

## Eko 2.0

Nova janela de ajustes inspirada nos Ajustes do Sistema: barra lateral translúcida com busca por seção, ícones coloridos, seleção azul, cabeçalho fixo e controles agrupados. O nome exibido e o executável agora são Eko.

Encerre o Lume antes de abrir Eko.app. O identificador e as chaves de preferências anteriores foram preservados para manter suas escolhas. O projeto mantém os nomes internos de arquivos do Lume; abra Lume.xcodeproj e use o esquema Lume para compilar Eko.app.

Histórico das versões anteriores abaixo.

## Atualização 1.10

- Indicadores organizados por cartões com ícones e legendas, mantendo o arraste.
- Na aba Música, controles independentes para Player flutuante e Player do Capsule: um deles, ambos ou nenhum. Desativar o flutuante mantém os metadados disponíveis para o Capsule.
- Texto e expansão do Capsule usam ease-in-out de 0,28 segundo, sem mola, com desfoque e transparência como ao esconder pelo mouse.

## Atualização 1.9

- Expansão contínua do espaço do texto, com o fundo acompanhando a largura e movimento amortecido.
- Capa com desfoque real na pausa e camada persistente do símbolo; retomar desfaz o efeito suavemente.
- Atualizações de música próximas são agrupadas por 90 ms. A capa permanece durante uma leitura sem imagem e a virada separa a troca da imagem da animação de retorno.
- A fluidez visual ainda requer confirmação no uso real; compilação não substitui inspeção da animação em uma sessão gráfica.

## Atualização 1.8

- Eventos de ajuste manual detectam a ação, mas o preenchimento usa a leitura normalizada de DisplayServices, na mesma escala do controle do app.
- Pausar mantém a capa desfocada com símbolo de pausa. Retomar a mesma faixa restaura a capa sem reabrir as informações.
- Ao montar o Capsule com uma faixa existente, o texto não é aberto. Mudanças de faixa durante a reprodução continuam revelando as informações, com transição somente de desfoque e transparência.
- Compilação não equivale à confirmação dos extremos de brilho na Touch Bar física; essa comparação ainda precisa ser realizada no uso real.

## Atualização 1.7

- A observação do brilho acompanha `DisplayServicesUserBrightness` por notificação e leitura a cada 50 ms, sem depender exclusivamente da notificação do estado final da tela.
- A classificação voltou a manter alterações de origem desconhecida silenciosas, além dos ajustes ambientais conhecidos.
- Os três balões compartilham a mesma instância visual. A animação da capa é cancelada ao remover o item e restaurada ao mudar o lado das informações.
- Eventos simulados de slider foram verificados sem uma notificação final de brilho. Isso não confirma a frequência com que o macOS publica essa propriedade durante o toque na Touch Bar física; essa validação permanece necessária.

## Atualização 1.6

- O nome da faixa, artista e álbum agora aparecem e desaparecem com uma transição simétrica de desfoque e transparência, seguindo o movimento visual do próprio Capsule.

## Atualização 1.5

- Mudanças de brilho sem uma marca de ajuste automático agora atualizam o balão imediatamente, como acontece com o volume.
- Somente eventos explicitamente identificados pelo macOS como automáticos, ambientais, ALS, térmicos ou de energia permanecem silenciosos.

## Atualização 1.4

- Nas configurações de Música no Capsule, as informações podem aparecer à esquerda ou à direita da capa.
- O texto mostra o nome da faixa e, abaixo, artista e álbum.
- A troca de faixa ganhou uma virada com profundidade e leve redução da capa; o texto entra pelo lado escolhido com expansão, movimento e desfoque mais suaves.

## Atualização 1.3

- O balão de brilho agora aparece desde o primeiro movimento e permanece visível durante todo o ajuste contínuo.
- Volume, brilho da tela e iluminação do teclado compartilham o mesmo tamanho, preenchimento, posição, entrada e saída; somente os ícones mudam.

## Atualização 1.2

- Novo item opcional **Música** na organização dos indicadores do Capsule.
- Durante a reprodução, ele mostra a capa do álbum. Ao iniciar ou trocar a faixa, a capa vira em 3D e revela título e artista com desfoque por alguns segundos.
- O item desaparece quando a reprodução para e respeita a opção Reduzir Movimento do macOS.
- Ativar o item Música também reativa o monitor do player, mantendo o filtro exclusivo para Spotify, Deezer e Apple Music.

## Atualização 1.1

- Escritas de brilho em segundo plano, priorizando o valor mais recente do arraste; ajustes pendentes são cancelados ao parar o serviço.
- Ajustes automáticos ou sem origem identificada não abrem os balões de brilho. Teclas, sliders do app e notificações identificadas como manuais continuam mostrando o indicador.
- A superfície de desfoque não intercepta os gestos do slider, e outros tipos de indicador não substituem um balão durante seu arraste.
- O ícone acompanha a saída de áudio ativa e válida; a identificação do FreeClip requer uma saída Bluetooth. Saídas indisponíveis não mantêm o ícone antigo.
- O balão de brilho da tela desaparece com transparência e desfoque, respeitando Reduzir Movimento.

Para instalar, encerre a versão anterior e extraia `Lume-v1.1.zip`. Os testes de 201 ajustes rápidos de brilho e de cancelamento de escritas pendentes passaram. A Touch Bar física, a detecção de fones e a resposta à luz ambiente ainda precisam ser confirmadas em uma sessão gráfica.

Lume reúne o Capsule 8, os indicadores de volume e brilho, o player e o arredondamento dos cantos em um aplicativo para Mac Intel com macOS Ventura ou mais recente.

## Abrir e configurar

1. Encerre o antigo `app` e o Status Capsule para não manter dois indicadores funcionando ao mesmo tempo.
2. Extraia `Lume.zip` e abra `Lume.app`. A janela de configurações aparece na primeira abertura.
3. Depois, use o ícone de brilhos na barra de menus e escolha **Configurações do Lume…**.
4. Em **Permissões**, autorize o Lume em Acessibilidade para usar as teclas com os HUDs. A autorização do aplicativo antigo pode não valer para o novo aplicativo.

## Configurações

- **Capsule:** ativação, tamanho de 75% a 160%, opacidade do fundo de 0% a 100%, porcentagem fixa ou automática ao conectar o carregador.
- **Indicadores:** ordem por arraste, Siri, Bluetooth e fones. O FreeClip utiliza o vetor aprovado. A associação manual da saída de áudio também é compartilhada entre HUD e Capsule.
- **Volume e brilho:** indicadores interativos e testes visuais. O controle experimental do indicador nativo da Touch Bar continua opcional e válido apenas na sessão atual.
- **Música:** somente os aplicativos Spotify (`com.spotify.client`), Deezer (`com.deezer.deezer-desktop`) e Apple Music (`com.apple.Music`). Versões web não são aceitas, porque sua origem é o navegador. Se uma fonte não permitida assume a reprodução do sistema, o player é limpo e seus comandos ficam bloqueados.
- **Tela:** ativação e raio dos cantos arredondados.

O tamanho do Capsule altera textos, ícones, espaçamento e fundo proporcionalmente. As preferências são salvas. Na primeira abertura, o Lume tenta importar as preferências conhecidas dos dois aplicativos anteriores.

## Validação e limites

Compilação Release para Intel e verificação de assinatura local. Testes realizados:

- filtro de origem do player, troca de aplicativo durante uma leitura, respostas antigas, desativação e comandos protegidos;
- disponibilidade dos símbolos de integração de mídia no macOS deste Mac;
- 500 ciclos simulados de energia e 100 notificações em segundo plano, atualizando a interface na fila principal;
- 201 movimentos rápidos do slider agrupados em duas escritas de volume, sem bloquear a interface;
- identificação de brilho manual/automático, callbacks antigos e leituras inválidas;
- watchdog testado exclusivamente contra um processo descartável: restauração por EOF, SIGTERM e perda do heartbeat.

Esses testes não equivalem a um teste visual com Spotify/Deezer/Apple Music reproduzindo, Touch Bar física, Siri ou carregador conectado. A sessão gráfica não estava disponível no ambiente de compilação. A integração de mídia e parte do brilho usam APIs privadas do macOS e podem exigir adaptação em futuras versões do sistema.

## Projeto e restauração

Abra `Lume.xcodeproj`, selecione o esquema Lume e execute. O auxiliar OSDGuardian é compilado junto com o aplicativo. Os testes em `Tests` são executáveis Swift independentes e não entram no app.

Os apps e projetos anteriores foram preservados. Para voltar, encerre o Lume e reabra as versões anteriores. O Lume utiliza o identificador `com.eduvini.lume`, separado dos antigos.

O código dos HUDs foi recuperado do histórico do projeto e recebeu novamente as correções de brilho e volume. O vetor do FreeClip vem da referência fornecida pelo usuário. A imagem da Siri com Apple Intelligence foi obtida da documentação da Apple: https://support.apple.com/guide/mac-help/turn-on-and-activate-siri-mchlb66b4ad6/26/mac/26 .
