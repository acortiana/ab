# ab

`ab` è una piccola CLI Bash che semplifica il ciclo di vita di container Docker
usati come **ambienti confinati e usa-e-getta**: shell interattiva, test,
prototipazione. È un wrapper sottile attorno a `docker`, con persistenza dei dati
su host in `home/` e `bin/`.

- **Eseguibile unico**: un solo script Bash autocontenuto.
- **Nessuna dipendenza** oltre a `docker` e agli strumenti standard di qualsiasi Linux.
- **KISS**: codice semplice, leggibile e modificabile anche da chi non programma.
- **UID/GID coerenti**: l'utente nel container ha lo stesso UID/GID dell'utente host,
  quindi i file in `home/` e `bin/` hanno ownership corretta senza `chown`.

## Requisiti

- `docker` installato e daemon in esecuzione (con permessi per l'utente corrente).
- Da eseguire come **utente non privilegiato** (non root).

## Installazione

Copia lo script `ab` in una directory nel tuo `PATH` e rendilo eseguibile:

```sh
install -m 755 ab ~/.local/bin/ab    # oppure /usr/local/bin/ab
```

## Modello operativo (git-like)

1. Crea una directory **vuota** dove vuoi sull'host.
2. Inizializzala con `ab init` (analogo a `git init`).
3. Esegui i comandi successivi **dall'interno** di quella directory.

Una directory inizializzata si riconosce dal file `.env` contenente la riga
`AB_PROJECT=true`. Fuori da una directory inizializzata, ogni comando diverso da
`init` esce con errore.

## Comandi

| Comando      | Descrizione                                                       |
|--------------|------------------------------------------------------------------|
| `ab init`    | Inizializza la directory corrente (solo interattivo)             |
| `ab create`  | Crea e avvia il container                                        |
| `ab destroy` | Distrugge il container (**non** tocca i dati su host)            |
| `ab shell`   | Apre una shell interattiva come utente non privilegiato         |
| `ab root`    | Apre una shell interattiva come root                            |

`shell` e `root` riavviano automaticamente il container se è fermo.

## Esempio

```sh
mkdir prova && cd prova
ab init        # rispondi alle domande (Invio = default)
ab create      # crea e avvia il container
ab shell       # entra come utente non privilegiato
# ... lavora ...
ab destroy     # rimuove il container; home/ e bin/ restano intatti
```

## `ab init`

Va eseguito in una directory **completamente vuota** (dot-file inclusi).
È interattivo: per ogni parametro mostra il default tra `[]`; premi Invio per
accettarlo o digita un valore alternativo.

| Parametro      | Default                              |
|----------------|--------------------------------------|
| Nome container | 8 caratteri alfanumerici casuali     |
| Immagine base  | `ubuntu:22.04`                       |
| Username       | `myuser`                             |
| Groupname      | `mygroup`                            |
| Comando avvio  | `sleep infinity`                     |
| Abilita X11    | `false`                              |
| Abilita Wayland| `false`                              |

UID e GID **non** si configurano: vengono letti a runtime dall'utente che esegue
`ab` (`id -u` / `id -g`).

`init` crea le sottodirectory `home/` e `bin/`, il file `.env` (letto a runtime)
e il file `.env.example` (riferimento documentale completo, mai letto da `ab`).

## Configurazione (`.env`)

```sh
AB_PROJECT=true            # marcatore di progetto, NON rimuovere
CONTAINER_NAME='...'       # nome del container
BASE_IMAGE='ubuntu:22.04'  # immagine base
USERNAME='myuser'          # utente non privilegiato nel container
GROUPNAME='mygroup'        # gruppo primario
CONTAINER_CMD='sleep infinity'  # comando principale (PID 1)
ENABLE_X11=false           # supporto grafico X11
ENABLE_WAYLAND=false       # supporto grafico Wayland
```

I valori testuali sono racchiusi tra apici singoli: quotali se contengono spazi o
caratteri speciali. Vedi `.env.example` per la documentazione completa di ogni chiave.

## Gestione di utente, gruppo e UID/GID

`ab create` usa **sempre** l'utente e il gruppo indicati nel `.env`, non quelli di
default dell'immagine. Il provisioning lavora direttamente su `/etc/passwd` e
`/etc/group` nel container (un solo metodo portabile su ogni distro — Ubuntu,
Debian, Fedora, Alpine — senza dipendere da `useradd`/`adduser`/`shadow`):

- crea il gruppo `GROUPNAME` con il **GID dell'host**;
- crea l'utente `USERNAME` con l'**UID dell'host**, gruppo primario `GROUPNAME`,
  home `/home/$USERNAME`;
- se un utente o un gruppo preesistenti **overlappano** (stesso nome, oppure stesso
  UID/GID dell'host), la riga in conflitto viene **rimossa e ricreata** corretta.

La shell di login dell'utente è `bash` se presente nell'immagine, altrimenti
`/bin/sh`: per questo `ab shell`/`ab root` funzionano anche su immagini senza
`bash` (es. Alpine "base").

## Supporto grafico

Configurabile nel `.env`, applicato da `ab create`. X11 e Wayland sono indipendenti
e attivabili insieme.

- **X11** (`ENABLE_X11=true`): monta `/tmp/.X11-unix` e l'`Xauthority` (in sola
  lettura), e passa `DISPLAY`/`XAUTHORITY`.
- **Wayland** (`ENABLE_WAYLAND=true`): monta il solo socket `wayland-0` e passa
  `WAYLAND_DISPLAY`/`XDG_RUNTIME_DIR`. Funziona perché il container usa lo stesso
  UID dell'host.

## Persistenza dei dati

- `./home` è montata su `/home/$USERNAME` nel container.
- `./bin` è montata su `/usr/local/bin` (utile per metterci script/eseguibili).
- `ab destroy` rimuove **solo** il container: `home/`, `bin/`, `.env` e
  `.env.example` non vengono mai toccati.

## Fuori scope

Networking/porte, variabili d'ambiente extra, volumi aggiuntivi, limiti di risorse,
multi-container, build di immagini custom, sottocomando `stop` (il container resta
attivo finché non viene distrutto; `shell`/`root` lo riavviano se fermo).
