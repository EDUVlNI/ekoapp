# Eko

**Volume, brilho, música e informações do Mac em uma interface discreta.**

O Eko reúne indicadores interativos, um Capsule com hora, bateria e conexões, dois modos de player e cantos de tela personalizáveis. Feito para Mac Intel com macOS Ventura 13 ou posterior.

[**Baixar Eko 2.2**](https://github.com/EDUVlNI/ekoapp/releases/download/v2.2/Eko-v2.2.zip) · [Configurações e histórico](LEIA-ME.md)

## Começar

1. Descompacte o download e mova **Eko.app** para **Aplicativos**.
2. Encerre uma versão anterior do Eko ou Lume antes de abrir.
3. Abra **Configurações do Eko…** pelo ícone na barra de menus.
4. Em **Permissões**, autorize Acessibilidade para usar as teclas de mídia com os indicadores.

A versão distribuída usa assinatura local e não é notarizada pela Apple.

## Controles rápidos

| Quero… | Como fazer |
| --- | --- |
| Ajustar volume ou brilho | Use as teclas do Mac ou arraste o controle do indicador. |
| Configurar os indicadores da Touch Bar | Abra **Volume e brilho** e ative a opção correspondente. |
| Organizar hora, bateria e conexões | Em **Indicadores**, arraste os cartões e escolha os itens visíveis. |
| Mudar tamanho e fundo | Use os controles de **Capsule**. |
| Exibir a porcentagem da bateria | Em **Capsule**, escolha a exibição permanente ou ao carregar. |
| Reproduzir, pausar ou trocar de faixa | Use os controles em **Música**, com um player compatível aberto. |
| Escolher onde a música aparece | Ative **Player flutuante**, **Player do Capsule** ou ambos. |
| Arredondar os cantos da tela | Em **Tela**, ative o efeito e ajuste o raio. |
| Encerrar o app | Selecione **Sair do Eko** na barra de menus. |

## Funcionalidades em ação

As demonstrações abaixo são animadas e podem ser vistas nesta página. Os GIFs mantêm as dimensões e a sequência de quadros dos vídeos enviados; o formato possui uma paleta de cores limitada. As demonstrações em resolução original são pesadas e podem demorar para carregar.

### Capsule: tamanho e fundo

Hora, Wi-Fi e bateria ficam juntos no topo da tela. Ajuste o tamanho do conjunto e a opacidade do fundo para combinar com sua Mesa. O Capsule se oculta quando a barra de menus aparece ou quando o mouse passa sobre ele; a Siri permanece clicável.

<img src="https://github.com/EDUVlNI/ekoapp/releases/download/v2.2/demo-capsule.gif" width="620" alt="Ajustes de tamanho e fundo do Capsule">

### Porcentagem da bateria

A porcentagem aparece ao lado do ícone com uma transição que acompanha a largura do Capsule.

<img src="https://github.com/EDUVlNI/ekoapp/releases/download/v2.2/demo-bateria-resumo.gif" width="350" alt="Exibição da porcentagem da bateria no Capsule">

### Indicadores na sua ordem

Arraste os cartões para reorganizar os indicadores. Ative os itens opcionais, como Música, Bluetooth, Siri e fones. Os fones aparecem quando há uma conexão identificada; as escolhas são salvas automaticamente.

<img src="https://github.com/EDUVlNI/ekoapp/releases/download/v2.2/demo-indicadores.gif" width="760" alt="Organização e seleção dos indicadores">

### Volume, brilho e iluminação do teclado

Os indicadores mostram o nível durante o ajuste, com controles interativos e uma apresentação consistente. A opção da Touch Bar pode ser configurada separadamente.

<img src="https://github.com/EDUVlNI/ekoapp/releases/download/v2.2/demo-volume-brilho.gif" width="760" alt="Indicadores de volume e brilho em uso">

### Indicadores do Eko ou do sistema

Ative ou desative os indicadores em **Volume e brilho** e compare o comportamento com o visual nativo do macOS. A integração experimental com o indicador nativo da Touch Bar é opcional e vale apenas para a sessão atual.

<img src="https://github.com/EDUVlNI/ekoapp/releases/download/v2.2/demo-controles-nativos.gif" width="760" alt="Alternância entre indicadores nativos e indicadores do Eko">

### Player flutuante

Acompanhe a capa, o título e o artista no topo da tela. O Eko reconhece Spotify, Deezer e Apple Music instalados no Mac. A gravação mostra reprodução, pausa e troca de faixa com Spotify.

<img src="https://github.com/EDUVlNI/ekoapp/releases/download/v2.2/demo-player-flutuante.gif" width="760" alt="Player flutuante com Spotify">

### Música no Capsule

Coloque a capa junto dos outros indicadores. A troca de faixa anima a capa e revela as informações; escolha se o texto aparece à esquerda ou à direita. O player do Capsule e o flutuante podem ser ativados independentemente.

<img src="https://github.com/EDUVlNI/ekoapp/releases/download/v2.2/demo-musica-capsule.gif" width="760" alt="Capa e informações musicais integradas ao Capsule">

### Economia de energia

O ícone da bateria acompanha o modo de pouca energia do macOS, usando amarelo quando ele está ativo. Essa opção é alterada nos Ajustes do Sistema; o Eko exibe o estado.

<img src="https://github.com/EDUVlNI/ekoapp/releases/download/v2.2/demo-economia-energia.gif" width="760" alt="Indicador acompanhando o modo de pouca energia">

### Preferências de bateria

Escolha entre manter a porcentagem sempre visível ou mostrá-la ao conectar o carregador. A configuração fica na seção **Capsule**.

<img src="https://github.com/EDUVlNI/ekoapp/releases/download/v2.2/demo-porcentagem-bateria.gif" width="760" alt="Opções de exibição da porcentagem da bateria">

### Cantos da tela

Ative o arredondamento e ajuste o raio para escolher a aparência dos cantos da tela.

<img src="https://github.com/EDUVlNI/ekoapp/releases/download/v2.2/demo-cantos-tela.gif" width="760" alt="Ajuste dos cantos arredondados da tela">

## Compilar pelo Terminal

Requer Xcode com SDK do macOS. Os nomes internos **Lume** foram mantidos para preservar a compatibilidade; o aplicativo gerado se chama **Eko.app**.

```sh
git clone https://github.com/EDUVlNI/ekoapp.git
cd ekoapp
xcodebuild -project Lume.xcodeproj -scheme Lume \
  -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Eko.app
```

Também é possível abrir `Lume.xcodeproj` no Xcode, selecionar **Lume** e executar.

## Compatibilidade

- Mac Intel, macOS 13 ou posterior. Touch Bar e bateria dependem do hardware disponível.
- Os players aceitos são os aplicativos de Spotify, Deezer e Apple Music; versões web não são reconhecidas como esses players.
- A integração de mídia e parte dos controles de brilho usam APIs privadas. O comportamento pode variar entre versões do macOS.
- O projeto inclui o auxiliar OSDGuardian. Touch Bar, ajustes automáticos e animações precisam ser validados numa sessão gráfica com hardware real.
- Os testes em `Tests` são executáveis Swift independentes; o esquema Xcode não configura uma suíte de testes.

Mais detalhes em [LEIA-ME.md](LEIA-ME.md).
