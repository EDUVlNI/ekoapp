# Eko

Aplicativo para Mac com indicadores de volume e brilho, Capsule com hora, bateria e conexões, e players para Spotify, Deezer e Apple Music.

## Baixar

[Baixar Eko 2.2 para Mac Intel](https://github.com/EDUVlNI/ekoapp/raw/refs/heads/main/releases/Eko-v2.2.zip)

Extraia o ZIP e abra `Eko.app`. Encerre uma versão anterior do Eko ou Lume antes de abrir esta versão. A compilação usa assinatura local, sem notarização Apple.

## Requisitos

- Mac Intel com macOS 13 ou mais recente.
- Xcode com SDK do macOS para compilar.
- Permissão de Acessibilidade para interceptar teclas de mídia.

## Compilar

Abra `Lume.xcodeproj`, selecione o esquema `Lume` e execute. O produto é `Eko.app`; alguns nomes internos foram mantidos para preservar a compatibilidade com as versões anteriores.

O projeto inclui o auxiliar OSDGuardian. A integração de mídia e parte dos controles de brilho usam APIs privadas do macOS. O comportamento de Touch Bar, ajuste automático e animações deve ser validado numa sessão gráfica com hardware real.

## Versão atual

Eko 2.2, com ícone de colagem sobre cortiça. Consulte [LEIA-ME.md](LEIA-ME.md) para configurações e histórico.

Os testes em `Tests` são executáveis Swift independentes. Não há configuração de testes automatizados no esquema Xcode.
