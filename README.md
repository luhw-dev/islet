# Islet

Dynamic Island para macOS — AppKit + SwiftUI, sem dependências externas.
Usa o notch físico do MacBook e desenha uma ilha equivalente em monitores externos.

Requer macOS 14+. O halo de vidro e o raio de canto do Tahoe pedem macOS 26,
com degradação automática em versões anteriores.

Licença MIT.

## Rodar

```sh
git clone <repo> && cd islet
./build-app.sh          # gera build/Islet.app
open build/Islet.app
```

O script assina com a primeira identidade Apple Development do chaveiro. Sem
identidade ele cai para assinatura ad-hoc e avisa — funciona, mas as permissões
precisam ser reconcedidas a cada build (o TCC passa a chavear pelo hash do
binário em vez da identidade).

O app não aparece no Dock (`LSUIElement`); a configuração fica no ícone da barra de menus.

Na primeira consulta ao player o macOS pede permissão de automação. Se for negada
por engano: Ajustes do Sistema › Privacidade e Segurança › Automação › Islet.

## O que já faz

- **Uma ilha por tela.** Notch real medido por `safeAreaInsets` + `auxiliaryTopLeftArea`;
  telas sem notch ganham uma pílula do mesmo formato (largura ajustável no menu).
- **Dois modos de ativação** (menu da barra):
  - *Passar o mouse expande* (padrão) — hover abre, sair fecha.
  - *Clicar expande* — o mouse não faz nada. A ilha recolhida vira três zonas:
    clique no **meio** (em cima do notch) abre e fecha; clique nas **laterais**
    toca/pausa a música direto, sem abrir. Aberta assim, fecha sozinha 5s
    depois que o cursor sai, para não ficar esquecida em cima da barra de menus.
- **Now playing** (Spotify e Música): capa, título, artista, barra de progresso
  arrastável (dá para pular no meio da faixa) e controles de aleatório, faixa,
  play/pause e saída de áudio. Recolhida, mostra a capa de um lado do notch e o
  waveform do outro — parar o mouse em cima do waveform troca ele pelo botão de
  pausa, um clique e pronto, sem abrir nada.
- **Cores tiradas da capa**: o waveform e a barra de progresso são tingidos com
  as duas matizes de mais peso do álbum que está tocando.
- **HUD de volume e brilho**: mexeu no volume ou no brilho, a ilha mostra na
  hora, com ícone de um lado do notch e barra do outro — e o HUD nativo do
  macOS fica escondido enquanto a Islet está aberta.
- **Troca de saída de áudio** pelo botão da direita, com a lista de dispositivos.
- **Aviso de troca de faixa**: a ilha abre sozinha por ~2,5s (desligável no menu).
- **Bateria**: anel com porcentagem, tempo até 100%, e abertura automática ao ligar na tomada.
- **Prateleira**: arraste arquivos para dentro da ilha e para fora, em outro app.

## Decisões que valem saber

**Os cantos são a squircle de verdade.** O macOS 26 Tahoe usa 26 pt nas janelas
com toolbar, no desenho concêntrico. Mas o raio sozinho não basta: a curva da
Apple é de curvatura contínua, e um arco quadrático comum entrega errado
justamente a transição para a reta. Em vez de aproximar superelipse na mão, o
`NotchShape` pega o path de um `RoundedRectangle(style: .continuous)` — que já é
a curva exata do sistema — e faz união de `CGPath` com as asas côncavas. O corpo
sobe 1,7 raio para fora da tela, senão a entrada da curva apareceria como uma
barriga nas laterais.

**MediaRemote está fechado.** `MRMediaRemoteGetNowPlayingInfo` só responde a binários
com entitlement da Apple desde o macOS 15.4 — testado aqui no 26.6 com o Spotify
tocando: o callback volta vazio. Por isso a fonte é o AppleScript de cada player,
com `DistributedNotificationCenter` (`com.spotify.client.PlaybackStateChanged`,
`com.apple.Music.playerInfo`) servindo de gatilho para atualizar na hora.
Se um dia o adapter com entitlement virar opção, dá para plugar como mais uma fonte
atrás de `MediaScripting`.

**Zonas de clique em vez de um modo "clique" genérico.** A ilha recolhida é
dividida em meio (abre/fecha) e laterais (play/pause), que é como a Dynamic
Island de verdade se comporta: tocar na pílula abre, tocar no indicador age.
Assim dá para pausar com um clique só, sem expandir nada.

**Clique atravessa a janela via `ignoresMouseEvents`.** Devolver `nil` no `hitTest`
faz o evento ser descartado, não repassado ao app de baixo — a janela cobre
560×240 pontos, então isso engolia cliques em volta do notch. O cursor é
acompanhado a 30 Hz e a janela só passa a aceitar mouse quando ele entra na ilha.

**A animação do equalizador vive em CALayer.** Em SwiftUI ela custava ~5% de CPU
o tempo todo, porque cada quadro disparava um ciclo de layout do AppKit na janela
inteira. Com `CABasicAnimation` a animação roda no render server. Em regime, com
música tocando e a ilha recolhida, o app fica em ~0,2% de CPU.

**Ler brilho é caro e não tem notificação pública.** `DisplayServicesGetBrightness`
(privado, mas acessível sem entitlement — diferente do MediaRemote) faz um XPC
síncrono para o CoreBrightness a cada chamada. Um benchmark em laço apertado
mede 42 µs e engana: no uso real, a 10 Hz, custava quase um ponto de CPU. Então
a amostragem é adaptativa — 5 Hz em repouso, 15 Hz por 2 s assim que o brilho
começa a mexer — e pega carona no timer do mouse, sem timer novo. Volume não tem
esse problema: o CoreAudio avisa por listener.

**Esconder o HUD nativo exige assumir as teclas.** No macOS 26 quem desenha o
popover de volume/brilho é o **Control Center**, não o `OSDUIHelper` — dá para
confirmar listando as janelas na tela durante a mudança. Não existe defaults,
API nem framework privado para desligá-lo. O único caminho é interceptar as
teclas de mídia com um event tap e aplicar a mudança por conta própria: se a
tecla não chega ao sistema, ele não tem o que desenhar.

Em troca, o app vira responsável por mudar volume e brilho de verdade. Por isso
a tecla só é engolida quando a mudança foi aplicada com sucesso — saída sem
controle de volume (certos HDMI) ou tela externa que não aceita brilho devolvem
a tecla ao sistema, que é melhor do que deixar a pessoa sem controle nenhum.

Isso exige **permissão de Acessibilidade** (Ajustes do Sistema › Privacidade e
Segurança). O app pede só ela; se o tap ainda for recusado com ela concedida,
escala para Monitoramento de Entrada — não faz sentido pedir mais do que o
necessário.

**Por isso o `build-app.sh` assina com identidade de desenvolvedor.** Com
assinatura ad-hoc o TCC guarda o hash do binário, então toda recompilação vira
"outro app" e derruba a autorização. Com identidade, ele guarda
`dev.aces.islet` + team, que não muda entre builds — verificado recompilando e
reabrindo sem tocar nos Ajustes. Sem identidade no chaveiro o script avisa e cai
para ad-hoc.

Para diagnosticar permissão: `launchctl setenv ISLET_LOG_FILE /tmp/islet.log`
antes de abrir o app. Pelo Finder ele não tem stderr, e é justamente aberto
assim que as permissões se comportam de verdade.

**Nota histórica: congelar o `OSDUIHelper` não funciona.** Quem desenha o quadrado de
volume/brilho do sistema é o `OSDUIHelper`, agente que o macOS sobe sob demanda,
e não há API para desligá-lo. Era o processo que desenhava o HUD até versões
anteriores do macOS, e congelá-lo com SIGSTOP resolvia. No Tahoe ele continua
existindo e sendo iniciado sob demanda, mas não é mais quem desenha — congelá-lo
não muda nada. O mecanismo foi removido.

**Os dois lados do HUD têm a mesma largura de propósito.** É isso que mantém o
vão do desenho em cima do notch físico, que é centralizado na tela: qualquer
assimetria desalinha os dois. Quem cede espaço é a barra, não o vão.

**O AppleScript é caro** (~75 ms por consulta, ida e volta de Apple Event até o
player), então o intervalo é adaptativo: 1s com a ilha aberta, 10s tocando e
recolhida, 20s parada. As notificações cobrem play/pause e troca de faixa.

## Variáveis de ambiente para desenvolver

| variável | efeito |
| --- | --- |
| `ISLET_FORCE_SIMULATED=1` | desenha a ilha simulada mesmo na tela com notch |
| `ISLET_OPEN_ON_LAUNCH=1` | já abre expandida (útil para screenshot) |
| `ISLET_STATIC_EQ=1` | congela o waveform |
| `ISLET_NO_BRIGHTNESS=1` | desliga a amostragem de brilho (para medir custo) |
| `ISLET_TRACE_INPUT=1` | loga hover, cliques e seek em stderr |
| `ISLET_TEST_SEEK=0.3` | pula para 30% da faixa 6 s após abrir, sem mouse |

## Estrutura

```
Core/
  IslandGeometry   medidas do notch/ilha e frame da janela por tela
  IslandWindow     NSPanel sem borda, acima da barra de menus, em todos os Spaces
  IslandController amarra tela + janela + estado; controla o click-through
  DisplayManager   uma ilha por tela, refaz tudo quando os monitores mudam
  MediaScripting   ponte AppleScript com Spotify e Música (fila serial)
  NowPlayingMonitor estado da reprodução, capa, progresso interpolado
  ArtworkPalette   histograma de matiz da capa -> cores do waveform/progresso
  SystemHUDMonitor volume (CoreAudio) e brilho (DisplayServices)
  AudioOutputManager lista e troca a saída de áudio
  BatteryMonitor   IOKit power sources
UI/
  NotchShape       o contorno com os cantos côncavos
  IslandView       raiz: alterna recolhido/expandido
  NowPlayingView   cabeçalho, scrubber, controles e waveform em CALayer
  ShelfView        arrastar e soltar arquivos
```

## Próximos passos naturais

- Marquee no título quando não couber.
- Mais fontes de mídia (Safari/Chrome não têm AppleScript de player; precisaria de outra via).
- Widgets: timer, área de transferência, AirDrop, calendário.
- Ajustes em janela própria em vez de só o menu.
- Iniciar com o sistema (`SMAppService`).
