<p align="center">
  <img src="docs/images/poki-icon.png" width="72" height="72" alt="Poki icon">
</p>

<h1 align="center">Poki usa tu iPhone como lo harías tú</h1>

<p align="center">
  <img src="docs/images/poki-home.gif" width="720" alt="Animación de la página de inicio del sitio web de Poki">
</p>

<p align="center">
  <a href="README.md">English</a> | <a href="README.zh-CN.md">简体中文</a> | <a href="README.zh-TW.md">繁體中文</a> | <a href="README.ja.md">日本語</a> | <a href="README.ko.md">한국어</a> | Español<br>
  <a href="https://poki.bot">poki.bot</a>
</p>

<!-- badges:start -->
<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0--only-blue" alt="License: AGPL-3.0-only"></a>
  <a href="https://github.com/JosssphZhou/poki/stargazers"><img src="https://img.shields.io/github/stars/JosssphZhou/poki" alt="GitHub stars"></a>
  <a href="https://github.com/JosssphZhou/poki/forks"><img src="https://img.shields.io/github/forks/JosssphZhou/poki" alt="GitHub forks"></a>
  <a href="https://github.com/JosssphZhou/poki/issues"><img src="https://img.shields.io/github/issues/JosssphZhou/poki" alt="GitHub issues"></a>
  <a href="https://github.com/JosssphZhou/poki/releases"><img src="https://img.shields.io/github/v/release/JosssphZhou/poki?sort=date&amp;display_name=release" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/platform-iOS%20%7C%20macOS%20%7C%20Windows-lightgrey" alt="Platform: iOS, macOS and Windows">
</p>
<!-- badges:end -->

Poki es un agente que usa un iPhone como lo hace una persona. Lee la pantalla, toca, escribe y desplaza el contenido de aplicaciones reales, y pide permiso antes de las acciones sensibles.

**La app de Poki** funciona en el propio iPhone. Le das una tarea en el chat y trabaja en tus otras aplicaciones. La instalas una vez desde un Mac o un PC con Windows y después ejecuta tareas sin el ordenador.

Poki MCP, la forma anterior de controlar un iPhone desde un agente en un Mac, ya no recibe actualizaciones. Conservamos las instrucciones para sus usuarios en [Poki MCP](#poki-mcp), al final de esta página.

Consulta los cambios de cada versión en [CHANGELOG.md](CHANGELOG.md).

## Instala Poki en tu iPhone

Necesitas un Mac o un PC con Windows para la instalación inicial.

- **En Mac**, pide a tu agente que instale Poki o descarga Poki Setup para macOS y sigue su ventana.
- **En Windows**, descarga Poki Setup para Windows. Instala primero Apple Devices o iTunes para que el PC reconozca el iPhone por USB. El agente también puede usar la herramienta de línea de comandos incluida en Poki Setup.
- **Después**, Poki ejecuta las tareas en el iPhone sin el ordenador. Con una cuenta de Apple gratuita, la firma dura 7 días y Poki Setup puede renovarla mientras permanece abierto en el ordenador. Consulta las [preguntas frecuentes](#preguntas-frecuentes).

### Con tu agente (recomendado)

Dile a Claude Code, Codex u otro agente:

```text
Instala Poki en mi iPhone desde https://github.com/JosssphZhou/poki
```

El agente sigue la [habilidad install-poki](skills/install-poki/SKILL.md) y ejecuta `bin/install-iphone.mjs` para completar los pasos que puede automatizar. Tú haces lo que requiere tu intervención: introducir tu cuenta de Apple en la ventana de Poki Setup del Mac, tocar Confiar, activar el modo de desarrollador, confiar en el desarrollador y abrir Poki en el iPhone. Al abrirlo por primera vez, Poki solicita Automation Mode. Toca Continue e introduce el código del iPhone. Si cancelas, vuelve a abrir Poki para recibir la solicitud de nuevo. El agente explica cada paso cuando lo necesitas. Una cuenta gratuita sirve.

El instalador usa Alpha salvo que pidas otro canal, como Beta. Cada compilación llega primero a Alpha y pasa a Beta después de más pruebas, sin cambiar el paquete.

¿No tienes Node.js 24 o usas Windows? Instala Poki Setup primero. La misma petición funciona con su herramienta de línea de comandos. También puedes copiar una petición desde Poki > Copy Prompt for Your Agent en Mac o Settings > Use an agent en Windows.

Si GitHub devuelve 403 o 429 al leer la lista de versiones, suele haberse agotado el límite horario de peticiones anónimas que comparte tu red. Cambia de red o de nodo de proxy y vuelve a intentarlo, o espera una hora.

### Con Poki Setup

Si prefieres hacerlo tú, descarga el `.dmg` para macOS o el `.exe` para Windows desde la [versión Alpha](https://github.com/JosssphZhou/poki/releases/tag/app-alpha-latest) y sigue su ventana. La versión de Windows es una contribución de [ZhehanZhang](https://github.com/ZhehanZhang). Beta incluye los mismos instaladores. Hasta que elijas un canal en los ajustes, Poki Setup instala la versión Stable más reciente o, si todavía no existe, la Beta. Consulta [Poki Setup](desktop/README.md) para ver los pasos.

### Qué necesitas

| Elemento | Requisito |
| --- | --- |
| iPhone | iOS 18 o posterior, es decir, iPhone XS, XR, SE de segunda generación o posterior. Las pruebas físicas se han hecho con iOS 27. |
| Ordenador | Mac con macOS 14 o posterior, o PC Windows x64 con Apple Devices o iTunes. La instalación mediante un agente en Mac también necesita Node.js 24 o posterior. No hace falta Xcode. |
| Cable y cuenta | Cable de datos USB y cuenta de Apple. La firma gratuita dura 7 días y Poki Setup puede renovarla. |
| Conexión | Una app VPN en el iPhone que dirija 10.7.0.1 al propio teléfono. Sirven LocalDevVPN, gratis en el App Store, o Karing y Shadowrocket configurados según las instrucciones de Poki. |
| Cuenta del modelo | Debes usar la tuya. Lo más sencillo es iniciar sesión con ChatGPT Plus o Pro. También puedes usar una clave API de Anthropic, OpenAI, Gemini, DeepSeek u OpenRouter, o tu propio servidor compatible con OpenAI. La suscripción de Claude no permite iniciar sesión; usa una clave API de Anthropic. |

En iOS 27 y posteriores, Poki usa los servicios nativos del iPhone. De iOS 18 a 26 usa una sesión XCTest, que requiere activar UI Automation en los ajustes de desarrollador. También se instala en iPad con iPadOS 18 o posterior.

### Preguntas frecuentes

**¿Puedo instalarlo desde Windows?** Sí. Poki Setup para Windows instala, empareja y renueva la firma igual que la versión para Mac. Instala antes Apple Devices o iTunes. Consulta [Poki Setup](desktop/README.md).

**¿Sigo necesitando el ordenador?** No para ejecutar tareas. Con una cuenta gratuita, mantén Poki Setup abierto para renovar la firma cada semana, o inicia sesión con tu cuenta de Apple en Poki para que el iPhone la renueve por sí mismo. El primer inicio de sesión puede fallar en 0.4.0. Consulta los [problemas conocidos](#problemas-conocidos) y [qué mantener en ejecución](skills/install-poki/SKILL.md#what-to-keep-running).

**¿Sirve una cuenta gratuita y qué significa el límite de 7 días?** Sí, pero Apple firma sus apps durante 7 días. Con Poki Setup abierto, el ordenador despierto y el iPhone accesible, se comprueba cada 6 horas y se renueva cuando quedan 2 días o menos. Sin renovación, la app deja de abrirse al caducar. Poki avisa durante los últimos 2 días. Consulta [la cuenta gratuita](skills/install-poki/SKILL.md#no-paid-developer-account).

**¿Qué iPhone y versión de iOS necesito?** iOS 18 o posterior en iPhone XS, XR, SE de segunda generación o posterior, o iPadOS 18 o posterior en iPad. Las pruebas físicas se han hecho solo con iOS 27. La ruta de control de iOS 18 a 26 todavía no se ha probado en un iPhone físico. Consulta la [verificación](docs/verification.md).

**¿Necesito mi propia cuenta de modelo?** Sí. Puedes usar ChatGPT Plus o Pro, las claves API de los proveedores indicados o tu propio servidor compatible con OpenAI. La conversación por voz también requiere una clave de un modelo de voz. Consulta [qué necesitas](#qué-necesitas).

**¿Qué hago si no aparece una actualización, por ejemplo en una red de China continental?** Poki consulta GitHub. Algunas redes no pueden acceder o reciben los límites 403 y 429. Cambia de red o de nodo de proxy, o usa Renew en Poki Setup desde el ordenador. Consulta [cómo actualizar Poki](#actualiza-poki).

**¿Cambia cosas en mi iPhone y pide permiso?** Trabaja en tus apps reales y ejecuta lo que pides, incluido enviar mensajes. El contenido de la pantalla se envía al servicio de modelo que configures. Los pagos, las eliminaciones y las acciones en Wallet siempre requieren confirmación. Para otros pasos, como enviar mensajes o escribir contraseñas, eliges cómo preguntar o si debe preguntar en Settings > Approvals. Consulta los [problemas conocidos](#problemas-conocidos).

## Actualiza Poki

- **En el iPhone**, abre Settings > Connection > Signing & Updates en 0.4.0, o la página Signing de los ajustes en 0.3.1. Si hay una compilación nueva, podrás descargarla e instalarla. Si pide iniciar sesión, el iPhone aún no tiene la cuenta usada al instalar desde el ordenador. Usa esa misma cuenta o actualiza desde el ordenador.
- **En el ordenador**, Renew en Poki Setup instala la última compilación del canal sobre la app existente. En Mac también puedes pedir al agente que actualice Poki. La ruta de actualización de install-poki comprueba primero la versión y la identidad de firma.
- Si se queda en “Finishing the update”, cierra Poki desde el selector de apps, vuelve a abrirlo y comprueba la versión. Si no cambió, actualiza con Poki Setup en el ordenador. No borres Poki para resolver una actualización, porque también borrarías las conversaciones.

Consulta los canales y el paso de Alpha a Beta en [Release channels](docs/release-channels.md).

## Problemas conocidos

- Poki opera tu iPhone real. Si le pides enviar mensajes o realizar pagos, lo hará. El contenido de la pantalla se envía al modelo que configures.
- En 0.4.0, el primer inicio de sesión con Apple en el iPhone puede indicar que necesitas un Mac. Apple dejó de aceptar la antigua identidad de Mac usada por Poki. Si ya has iniciado sesión, la actualización en el iPhone funciona como antes. En otro caso, renueva y actualiza desde Poki Setup en el ordenador.
- Solo se ha verificado el soporte físico con iPhones en chino y en orientación vertical. La orientación horizontal no está soportada.
- No se ha probado esta versión en dispositivos físicos con iOS anterior a 27 ni en iPad. En iPhones antiguos o pequeños, el oso tridimensional y las animaciones pueden generar más calor o funcionar más despacio. El modo de bajo consumo y Reducir movimiento muestran una imagen estática del oso.
- La firma gratuita dura 7 días. Mantén Poki Setup en el ordenador con acceso al iPhone o renueva manualmente antes del vencimiento.
- La lista de versiones de GitHub puede fallar con 403 o 429, a menudo por compartir red. Cambia de red o de nodo de proxy, o espera una hora.

Consulta más límites y resultados en [Verification](docs/verification.md).

## Prueba una tarea

Abre Poki y escribe “Consulta el tiempo de mañana y dime si necesito un paraguas”, o toca una app en la página de inicio. Poki trabaja en la app de la pantalla, muestra los pasos en Dynamic Island y en la pantalla bloqueada, y pide permiso antes de una acción sensible.

También puedes mantener pulsado el botón de acción para hablar, o usar Talk to Poki y Send Task to Poki desde Atajos y Siri sin abrir primero la app. Esas tareas responden mediante una notificación.

> **Nota:** Poki controla tu iPhone real. Si le pides enviar mensajes o realizar pagos, lo hará.

## Hoja de ruta

Son direcciones de trabajo, no fechas prometidas.

**Completado hasta 0.4.0 Beta**

- App de iPhone que funciona sin Mac tras la configuración, con aprobaciones en la pantalla bloqueada y Dynamic Island.
- Instalación con un agente o Poki Setup en Mac y Windows, sin Xcode y con cuenta gratuita.
- Control nativo en iOS 27 y posteriores.
- Poki MCP, Poki Agent, canales iMessage y Telegram, y aprendizaje y repetición de rutas. Poki MCP se conserva sin nuevas actualizaciones.
- Conexiones remotas por LAN y Tailscale.
- Interfaz 0.4.0 con oso tridimensional, voz, botón de acción, archivo y modo oscuro.

**Lo siguiente**

- Fuente de descarga propia, con GitHub de respaldo.
- Un único canal de actualización.
- La voz escucha, habla y mira; las acciones se delegan en los modelos de texto que ejecutan las tareas actuales.
- Más idiomas de interfaz.

**Más adelante**

- Verificación física de más iPhones, versiones de iOS e idiomas.
- Más proveedores de modelos.

## Documentación

| Tema | Documento |
| --- | --- |
| Cambios de cada versión | [CHANGELOG.md](CHANGELOG.md) |
| Instalar la app con un agente | [install-poki](skills/install-poki/SKILL.md) |
| Instalador para Mac y Windows | [Poki Setup](desktop/README.md) |
| Canales y promoción de compilaciones | [Release channels](docs/release-channels.md) |
| Instalación, clientes y problemas de Poki MCP (sin nuevas actualizaciones) | [Install guide](docs/install.md) |
| Poki Agent, modelos, iMessage y Telegram | [Run Poki Agent](agent/README.md) |
| Herramientas MCP | [Tool behavior](docs/tools.md) |
| Variables y sesiones | [Configuration](docs/configuration.md) |
| USB, modo de desarrollador y Wi-Fi | [Physical iPhone setup](docs/physical-iphone.md) |
| Pruebas, límites y avisos | [Verification](docs/verification.md) |
| Arquitectura del puente | [Native bridge](native/NATIVE.md) y [simulator adapter](native/simulator.md) |
| Hoja de ruta | [Hoja de ruta](#hoja-de-ruta) |

## Star History

<a href="https://www.star-history.com/?repos=JosssphZhou%2Fpoki&type=date&legend=top-left">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=JosssphZhou/poki&type=date&theme=dark&legend=top-left">
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=JosssphZhou/poki&type=date&legend=top-left">
    <img alt="Star History chart" src="https://api.star-history.com/chart?repos=JosssphZhou/poki&type=date&legend=top-left">
  </picture>
</a>

## Colaboradores principales

<!-- CORE-CONTRIBUTORS:START -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/makirqi-alt"><img src="https://avatars.githubusercontent.com/u/295395617?v=4&size=240" width="120" height="120" alt="makirqi-alt"/><br /><sub><b>makirqi-alt</b></sub></a><br />Abrió el primer issue de Poki, <a href="https://github.com/JosssphZhou/poki/issues/1">#1</a>, en iOS 18.6.2: las capturas funcionaban, la accesibilidad y el toque no, y la separación clara lo hizo fácil de seguir.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/ZhehanZhang"><img src="https://avatars.githubusercontent.com/u/67270559?v=4&size=240" width="120" height="120" alt="ZhehanZhang"/><br /><sub><b>ZhehanZhang</b></sub></a><br />El gran cocreador de Poki.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/edge369"><img src="https://avatars.githubusercontent.com/u/63720633?v=4&size=240" width="120" height="120" alt="edge369"/><br /><sub><b>edge369</b></sub></a><br />Hizo que Poki funcionara en un router en <a href="https://github.com/JosssphZhou/poki/pull/14">#14</a>, de modo que Telegram controla el iPhone con el Mac apagado; siguieron <a href="https://github.com/JosssphZhou/poki/pull/15">#15</a>, <a href="https://github.com/JosssphZhou/poki/pull/17">#17</a> y <a href="https://github.com/JosssphZhou/poki/issues/19">#19</a>.</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/mawenhao1028"><img src="https://avatars.githubusercontent.com/u/70818670?v=4&size=240" width="120" height="120" alt="mawenhao1028"/><br /><sub><b>mawenhao1028</b></sub></a><br />Informó en <a href="https://github.com/JosssphZhou/poki/issues/6">#6</a> de que usbmuxd no listaba ningún iPhone en macOS 27.2; ahora Poki lo dice con claridad y explica por qué un ayudante se detiene antes de tiempo (<a href="https://github.com/JosssphZhou/poki/issues/59">#59</a>).</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/igc110"><img src="https://avatars.githubusercontent.com/u/241411380?v=4&size=240" width="120" height="120" alt="igc110"/><br /><sub><b>igc110</b></sub></a><br />Descubrió en <a href="https://github.com/JosssphZhou/poki/issues/10">#10</a> por qué los toques en un iPhone físico eran lentos; la corrección posterior los hizo alrededor de un tercio más rápidos.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/carrotciallo"><img src="https://avatars.githubusercontent.com/u/69567867?v=4&size=240" width="120" height="120" alt="carrotciallo"/><br /><sub><b>carrotciallo</b></sub></a><br />Portó Poki a Linux y lo probó en un iPhone físico por USB, LAN y Tailscale en <a href="https://github.com/JosssphZhou/poki/issues/16">#16</a>; el README ahora lo enlaza.</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/guangtouge82"><img src="https://avatars.githubusercontent.com/u/269691899?v=4&size=240" width="120" height="120" alt="guangtouge82"/><br /><sub><b>guangtouge82</b></sub></a><br />Rastreó en <a href="https://github.com/JosssphZhou/poki/issues/18">#18</a> los toques fallidos de un iPhone físico hasta la falta de display service; ahora Poki indica que no se envió nada y apunta a prepare-device.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/Dreaminmaster"><img src="https://avatars.githubusercontent.com/u/189544503?v=4&size=240" width="120" height="120" alt="Dreaminmaster"/><br /><sub><b>Dreaminmaster</b></sub></a><br />Corrigió una ruta en caché corrupta que abortaba tareas del Agent sin relación (<a href="https://github.com/JosssphZhou/poki/issues/21">#21</a>, <a href="https://github.com/JosssphZhou/poki/pull/22">#22</a>) y después hizo que el Agent reutilice la pantalla ya leída tras cada acción (<a href="https://github.com/JosssphZhou/poki/pull/37">#37</a>).</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/PeterKingXu1s"><img src="https://avatars.githubusercontent.com/u/89392314?v=4&size=240" width="120" height="120" alt="PeterKingXu1s"/><br /><sub><b>PeterKingXu1s</b></sub></a><br />Reportó en <a href="https://github.com/JosssphZhou/poki/issues/25">#25</a> que una petición de detener en lenguaje natural no interrumpía una tarea de iMessage; ahora Poki responde a los mensajes enviados durante la tarea y señala /stop.</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/ScottH1122"><img src="https://avatars.githubusercontent.com/u/142722955?v=4&size=240" width="120" height="120" alt="ScottH1122"/><br /><sub><b>ScottH1122</b></sub></a><br />Reprodujo dos errores del Agent en <a href="https://github.com/JosssphZhou/poki/issues/27">#27</a> y <a href="https://github.com/JosssphZhou/poki/issues/28">#28</a> y luego fusionó siete correcciones y arreglos de pruebas, desde bloqueos de entrada cancelados (<a href="https://github.com/JosssphZhou/poki/pull/102">#102</a>) hasta coordenadas táctiles no válidas (<a href="https://github.com/JosssphZhou/poki/pull/136">#136</a>).</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/jiahuipaung"><img src="https://avatars.githubusercontent.com/u/70688286?v=4&size=240" width="120" height="120" alt="jiahuipaung"/><br /><sub><b>jiahuipaung</b></sub></a><br />Corrigió en <a href="https://github.com/JosssphZhou/poki/pull/34">#34</a> una conexión RemotePairing que fallaba al cambiar la dirección LAN del iPhone (<a href="https://github.com/JosssphZhou/poki/issues/30">#30</a>); un iPhone real se reconectó en 768 ms.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/Zeno6898"><img src="https://avatars.githubusercontent.com/u/229920081?v=4&size=240" width="120" height="120" alt="Zeno6898"/><br /><sub><b>Zeno6898</b></sub></a><br />Probó la app de iPhone con datos móviles y desde Windows en <a href="https://github.com/JosssphZhou/poki/issues/35">#35</a> y <a href="https://github.com/JosssphZhou/poki/issues/40">#40</a>, lo que dio lugar a la nota sobre Wi-Fi en la primera configuración (<a href="https://github.com/JosssphZhou/poki/issues/138">#138</a>); también informó de <a href="https://github.com/JosssphZhou/poki/issues/162">#162</a>.</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/scy7796"><img src="https://avatars.githubusercontent.com/u/282529358?v=4&size=240" width="120" height="120" alt="scy7796"/><br /><sub><b>scy7796</b></sub></a><br />Corrigió en <a href="https://github.com/JosssphZhou/poki/pull/39">#39</a> los toques que fallaban siempre por RemotePairing desde un host Windows; después, 5 de 5 toques funcionaron.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/foshanfm"><img src="https://avatars.githubusercontent.com/u/24779370?v=4&size=240" width="120" height="120" alt="foshanfm"/><br /><sub><b>foshanfm</b></sub></a><br />Hizo en <a href="https://github.com/JosssphZhou/poki/issues/42">#42</a> una comprobación de condiciones de seguros en un iPhone real por Tailscale; su informe orientó errores USB más claros y un cambio de transporte por sesión.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/xiaweiyi713"><img src="https://avatars.githubusercontent.com/u/208608622?v=4&size=240" width="120" height="120" alt="xiaweiyi713"/><br /><sub><b>xiaweiyi713</b></sub></a><br />Grabó vídeos de demostración de Poki controlando un iPhone real, para que los visitantes nuevos vean qué hace antes de instalar nada.</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/fucknima"><img src="https://avatars.githubusercontent.com/u/18666223?v=4&size=240" width="120" height="120" alt="f&#42;&#42;&#42;&#42;&#42;&#42;&#42;"/><br /><sub><b>f&#42;&#42;&#42;&#42;&#42;&#42;&#42;</b></sub></a><br />Añadió OpenCode Go como cuenta de modelo en la app de iPhone en <a href="https://github.com/JosssphZhou/poki/pull/68">#68</a>, con su propia credencial en el llavero y una elección de modelo independiente.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/owensn951954688"><img src="https://avatars.githubusercontent.com/u/312761798?v=4&size=240" width="120" height="120" alt="owensn951954688"/><br /><sub><b>owensn951954688</b></sub></a><br />Aportó en <a href="https://github.com/JosssphZhou/poki/issues/69">#69</a> la cronología completa de un fallo de emparejamiento del Runner tras 25 minutos de inactividad; Setup ahora remite a Loopback y Pairing (<a href="https://github.com/JosssphZhou/poki/issues/70">#70</a>).</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/kira-ariaki"><img src="https://avatars.githubusercontent.com/u/257352493?v=4&size=240" width="120" height="120" alt="kira-ariaki"/><br /><sub><b>kira-ariaki</b></sub></a><br />Hizo que las llamadas por lotes avisen de un dispositivo ambiguo en vez de fallar (<a href="https://github.com/JosssphZhou/poki/pull/74">#74</a>) y añadió POKI_MCP_DEVICE (<a href="https://github.com/JosssphZhou/poki/pull/75">#75</a>) y una aprobación opcional por tarea (<a href="https://github.com/JosssphZhou/poki/pull/77">#77</a>).</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/Purelite"><img src="https://avatars.githubusercontent.com/u/9334469?v=4&size=240" width="120" height="120" alt="Purelite"/><br /><sub><b>Purelite</b></sub></a><br />Corrigió que la configuración del emparejamiento llevara a la página de Ajustes equivocada; los pasos de Modo desarrollador y automatización de UI ahora abren la correcta (<a href="https://github.com/JosssphZhou/poki/pull/137">#137</a>).</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/heyallencao"><img src="https://avatars.githubusercontent.com/u/258265534?v=4&size=240" width="120" height="120" alt="heyallencao"/><br /><sub><b>heyallencao</b></sub></a><br />Corrigió en <a href="https://github.com/JosssphZhou/poki/pull/139">#139</a> las lecturas de pantalla que superaban el plazo de la llamada, con una prueba de regresión para respuestas del Runner constantemente lentas.</td>
    </tr>
  </tbody>
</table>
<!-- CORE-CONTRIBUTORS:END -->

## Colaboradores especiales

<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/yulunRyanw"><img src="https://avatars.githubusercontent.com/u/216360668?v=4&size=240" width="120" height="120" alt="yulunRyanw"/><br /><sub><b>yulunRyanw</b></sub></a><br />Aportó un conjunto completo de diseños para la renovación 0.4.0, desde el chat y Live Activity hasta los ajustes y el primer inicio (<a href="https://github.com/JosssphZhou/poki/pull/250">#250</a>, <a href="https://github.com/JosssphZhou/poki/pull/256">#256</a> a <a href="https://github.com/JosssphZhou/poki/pull/268">#268</a>). Sus diseños dieron forma a la dirección de la nueva interfaz.</td>
    </tr>
  </tbody>
</table>


## Menciones especiales

Gracias a todas las personas que han abierto un issue o un pull request; sus reportes y correcciones hacen que Poki sea cada vez mejor.

<!-- THANKS-WALL:START -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="20%"><a href="https://github.com/ZhehanZhang"><img src="https://avatars.githubusercontent.com/u/67270559?v=4&size=160" width="80" height="80" alt="ZhehanZhang"/><br /><sub><b>ZhehanZhang</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/carrotciallo"><img src="https://avatars.githubusercontent.com/u/69567867?v=4&size=160" width="80" height="80" alt="carrotciallo"/><br /><sub><b>carrotciallo</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/Dreaminmaster"><img src="https://avatars.githubusercontent.com/u/189544503?v=4&size=160" width="80" height="80" alt="Dreaminmaster"/><br /><sub><b>Dreaminmaster</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/edge369"><img src="https://avatars.githubusercontent.com/u/63720633?v=4&size=160" width="80" height="80" alt="edge369"/><br /><sub><b>edge369</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/foshanfm"><img src="https://avatars.githubusercontent.com/u/24779370?v=4&size=160" width="80" height="80" alt="foshanfm"/><br /><sub><b>foshanfm</b></sub></a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="20%"><a href="https://github.com/fucknima"><img src="https://avatars.githubusercontent.com/u/18666223?v=4&size=160" width="80" height="80" alt="f&#42;&#42;&#42;&#42;&#42;&#42;&#42;"/><br /><sub><b>f&#42;&#42;&#42;&#42;&#42;&#42;&#42;</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/guangtouge82"><img src="https://avatars.githubusercontent.com/u/269691899?v=4&size=160" width="80" height="80" alt="guangtouge82"/><br /><sub><b>guangtouge82</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/heyallencao"><img src="https://avatars.githubusercontent.com/u/258265534?v=4&size=160" width="80" height="80" alt="heyallencao"/><br /><sub><b>heyallencao</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/htx996"><img src="https://avatars.githubusercontent.com/u/95217139?v=4&size=160" width="80" height="80" alt="htx996"/><br /><sub><b>htx996</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/igc110"><img src="https://avatars.githubusercontent.com/u/241411380?v=4&size=160" width="80" height="80" alt="igc110"/><br /><sub><b>igc110</b></sub></a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="20%"><a href="https://github.com/iTry"><img src="https://avatars.githubusercontent.com/u/1381960?v=4&size=160" width="80" height="80" alt="iTry"/><br /><sub><b>iTry</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/jiahuipaung"><img src="https://avatars.githubusercontent.com/u/70688286?v=4&size=160" width="80" height="80" alt="jiahuipaung"/><br /><sub><b>jiahuipaung</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/kilingzhang"><img src="https://avatars.githubusercontent.com/u/17439300?v=4&size=160" width="80" height="80" alt="kilingzhang"/><br /><sub><b>kilingzhang</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/kira-ariaki"><img src="https://avatars.githubusercontent.com/u/257352493?v=4&size=160" width="80" height="80" alt="kira-ariaki"/><br /><sub><b>kira-ariaki</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/lunar-me"><img src="https://avatars.githubusercontent.com/u/275556969?v=4&size=160" width="80" height="80" alt="lunar-me"/><br /><sub><b>lunar-me</b></sub></a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="20%"><a href="https://github.com/makirqi-alt"><img src="https://avatars.githubusercontent.com/u/295395617?v=4&size=160" width="80" height="80" alt="makirqi-alt"/><br /><sub><b>makirqi-alt</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/mawenhao1028"><img src="https://avatars.githubusercontent.com/u/70818670?v=4&size=160" width="80" height="80" alt="mawenhao1028"/><br /><sub><b>mawenhao1028</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/oasis979559-alt"><img src="https://avatars.githubusercontent.com/u/295108220?v=4&size=160" width="80" height="80" alt="oasis979559-alt"/><br /><sub><b>oasis979559-alt</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/owensn951954688"><img src="https://avatars.githubusercontent.com/u/312761798?v=4&size=160" width="80" height="80" alt="owensn951954688"/><br /><sub><b>owensn951954688</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/PeterKingXu1s"><img src="https://avatars.githubusercontent.com/u/89392314?v=4&size=160" width="80" height="80" alt="PeterKingXu1s"/><br /><sub><b>PeterKingXu1s</b></sub></a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="20%"><a href="https://github.com/Purelite"><img src="https://avatars.githubusercontent.com/u/9334469?v=4&size=160" width="80" height="80" alt="Purelite"/><br /><sub><b>Purelite</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/ScottH1122"><img src="https://avatars.githubusercontent.com/u/142722955?v=4&size=160" width="80" height="80" alt="ScottH1122"/><br /><sub><b>ScottH1122</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/scy7796"><img src="https://avatars.githubusercontent.com/u/282529358?v=4&size=160" width="80" height="80" alt="scy7796"/><br /><sub><b>scy7796</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/wanghao-SunSky"><img src="https://avatars.githubusercontent.com/u/73684879?v=4&size=160" width="80" height="80" alt="wanghao-SunSky"/><br /><sub><b>wanghao-SunSky</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/windywendyday"><img src="https://avatars.githubusercontent.com/u/65647922?v=4&size=160" width="80" height="80" alt="windywendyday"/><br /><sub><b>windywendyday</b></sub></a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="20%"><a href="https://github.com/xiaweiyi713"><img src="https://avatars.githubusercontent.com/u/208608622?v=4&size=160" width="80" height="80" alt="xiaweiyi713"/><br /><sub><b>xiaweiyi713</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/yulunRyanw"><img src="https://avatars.githubusercontent.com/u/216360668?v=4&size=160" width="80" height="80" alt="yulunRyanw"/><br /><sub><b>yulunRyanw</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/zcyoung2000"><img src="https://avatars.githubusercontent.com/u/62181891?v=4&size=160" width="80" height="80" alt="zcyoung2000"/><br /><sub><b>zcyoung2000</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/Zeno6898"><img src="https://avatars.githubusercontent.com/u/229920081?v=4&size=160" width="80" height="80" alt="Zeno6898"/><br /><sub><b>Zeno6898</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/zqy5608"><img src="https://avatars.githubusercontent.com/u/14949471?v=4&size=160" width="80" height="80" alt="zqy5608"/><br /><sub><b>zqy5608</b></sub></a></td>
    </tr>
  </tbody>
</table>
<!-- THANKS-WALL:END -->

<a id="poki-mcp"></a>

## Poki MCP (conexión anterior desde el ordenador, sin actualizaciones)

Poki MCP es la conexión anterior desde un ordenador y ya no recibe actualizaciones. Un agente en el Mac, como Claude Code o Codex, controla el iPhone o iOS Simulator, y Poki Agent ofrece el terminal y los canales iMessage y Telegram. Se conserva para usuarios existentes y desarrolladores. Para la versión que sigue en mantenimiento, [instala la app de iPhone](#instala-poki-en-tu-iphone).

**Deja que tu agente lo instale.** Copia esto a tu agente:

```text
Instala https://github.com/JosssphZhou/poki siguiendo el AGENTS.md de la raíz, incluida la skill de MCP, y detente cada vez que necesites que yo haga algo.
```

**Poki MCP.** ¿Ya usas Claude Code, Codex u otro cliente MCP? Conecta Poki MCP y usa tu propia suscripción. No necesitas otra cuenta de modelos.

Inicia el servidor y déjalo en ejecución:

```sh
git clone https://github.com/JosssphZhou/poki.git
cd poki
./bin/setup
npm start
```

Poki MCP se compila desde el código fuente y requiere macOS 15 o posterior, Xcode completo, Rust, Node.js 24+, Python 3 y ffmpeg. La app de Poki no necesita Xcode. `./bin/setup` comprueba las dependencias y la primera compilación tarda unos minutos.

Poki está pensado para macOS. Para Linux, consulta el port de la comunidad [poki-for-linux](https://github.com/carrotciallo/poki-for-linux) ([#16](https://github.com/JosssphZhou/poki/issues/16)), que se mantiene fuera de este repositorio.

Poki MCP on Windows: port de la comunidad en [scy7796/poki-for-windows](https://github.com/scy7796/poki-for-windows) (mantenido por su autor, no probado por nosotros).

Las versiones de Poki MCP usan etiquetas `vX.Y.Z`. Las versiones `app-` del iPhone no incluyen este paquete.

### Paquete precompilado para macOS arm64

Descarga [`poki-v0.1.1-macos-arm64.tar.gz`](https://github.com/JosssphZhou/poki/releases/tag/v0.1.1) desde la release y ejecuta:

```sh
tar -xzf poki-v0.1.1-macos-arm64.tar.gz
cd poki-v0.1.1
npm ci --no-audit --no-fund
npm start
```

El paquete incluye el puente nativo y las herramientas de idevice. No necesitas Rust ni `./bin/setup`. Sigues necesitando macOS en Apple Silicon, Xcode completo, Node.js 24+, Python 3 y ffmpeg. Registra tu cliente MCP e instala el Agent opcional como se describe más abajo.

En otra terminal, desde el mismo directorio, registra el servidor MCP:

```sh
claude mcp add --scope user poki-mcp -- node "$PWD/src/stdio.mjs"   # Claude Code
codex mcp add poki-mcp -- node "$PWD/src/stdio.mjs"                 # Codex
```

**Poki Agent.** Para usar el agente de terminal independiente de Poki o sus canales de mensajería, deja `npm start` en ejecución y abre otra terminal en el mismo directorio. Instala el agente, añade su comando al PATH de esta terminal e inicia sesión:

```sh
npm ci --prefix agent
export PATH="$PWD/bin:$PATH"
poki login
poki status
```

Poki Agent usa GPT-6.1 Terra (`gpt-6.1-terra`) con razonamiento low de forma predeterminada. Recomendamos mantener esta configuración: es la más rápida que hemos probado para tareas en el teléfono. Puedes cambiar el modelo con `POKI_AGENT_MODEL`; consulta [Ejecutar Poki Agent](agent/README.md).

Para un iPhone físico, primero emparéjalo con tu Mac por USB. Consulta [Configuración del iPhone físico](docs/physical-iphone.md).

`./bin/poki update` sigue descargando el main más reciente y recompilando. Consulta [Update](AGENTS.md#update) para reiniciar y configurar la comprobación opcional de actualizaciones.

### Prueba una tarea con Poki Agent

Con Poki Agent, si hay un solo iPhone conectado, se selecciona automáticamente. Con varios dispositivos, añade `--device '<device UUID>'`.

```sh
node bin/call.mjs list_devices   # Busca el UUID de tu dispositivo
poki "Search esp32 in Chrome and summarize the top result"
```

> **Nota:** Poki controla tu iPhone real. Si le pides que envíe mensajes o haga pagos, lo hará. El contenido de la pantalla se envía al servicio de modelos que hayas configurado.

Cada vez más rápido: Poki Agent recuerda las tareas anteriores y las ejecuta más rápido al repetirlas.

**Canales:** Tras configurar un canal autorizado, inícialo con `poki imessage` o [`poki telegram`](agent/README.md#telegram). Consulta [Poki Agent](agent/README.md) para la configuración.

**Clientes MCP:** Claude Code, Codex y cualquier cliente compatible con JSON de `mcpServers`.

La compatibilidad con iPhone físico solo se ha verificado en iPhone con la interfaz en chino. Los dispositivos físicos solo admiten orientación vertical. No están disponibles la exportación de contenedores de apps ni los enlaces directos a subpáginas de Ajustes. Consulta [verificación y límites conocidos](docs/verification.md).

## Descargo de responsabilidad

Poki es un proyecto independiente de código abierto. No está afiliado a Apple, OpenAI ni a los creadores de ninguna app o sitio web que opere, ni cuenta con su respaldo. iPhone es una marca comercial de Apple Inc.

Automatizar apps y sitios web de terceros puede infringir sus condiciones de servicio. Decide por tu cuenta si usas Poki con un servicio determinado. Eres responsable de lo que haga en tu dispositivo y tus cuentas, incluidos los mensajes que envíe, los cambios que realice y cualquier restricción de cuenta que se derive de ello.

Poki se proporciona «tal cual», sin garantía, según lo establecido en la licencia AGPL-3.0.

En caso de ambigüedad, prevalece la versión en inglés.

## Licencia

El código de Poki es código abierto bajo la [licencia AGPL-3.0-only](LICENSE).

El oso de Poki, el icono de la app y el resto de las ilustraciones de Poki no están cubiertos por esa licencia. Puedes usar capturas de pantalla para hablar de Poki; un fork necesita su propio nombre y sus propias ilustraciones. Consulta [BRAND.md](BRAND.md).

Copyright (c) 2026 Joseph Zhou (周瑟夫) and contributors. Las dependencias de código abierto y los recursos de terceros conservan sus respectivas licencias; consulta [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Para contribuir, consulta [CONTRIBUTING.md](CONTRIBUTING.md).

## Agradecimientos

<p align="center">
  <img src="docs/images/acknowledgments.png" width="860" alt="Creado con código abierto: pi, idevice, idb, BlueBubbles, Hermes Agent, MCP SDK, sharp y FFmpeg"><br>
  <sub>Agradecimientos al código abierto: <a href="https://github.com/earendil-works/pi">pi</a> | <a href="https://github.com/jkcoxson/idevice">idevice</a> | <a href="https://github.com/facebook/idb">idb</a> | <a href="https://github.com/BlueBubblesApp/bluebubbles-server">BlueBubbles</a> | <a href="https://github.com/NousResearch/hermes-agent">Hermes Agent</a> | <a href="https://github.com/modelcontextprotocol/typescript-sdk">MCP SDK</a> | <a href="https://github.com/lovell/sharp">sharp</a> | <a href="https://github.com/FFmpeg/FFmpeg">FFmpeg</a></sub>
</p>
