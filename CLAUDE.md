# CLAUDE.md

Guida per lavorare su questo repository. Leggi anche `README.md` per l'uso utente.

## Cos'è

`ab` è una CLI Bash che fa da wrapper sottile attorno a `docker` per gestire
container usa-e-getta. **Tutto il codice è nel singolo file `ab`** (eseguibile
Bash autocontenuto). Non c'è build, non ci sono dipendenze oltre a `docker` e agli
strumenti standard di un qualsiasi Linux.

## Principi NON negoziabili

- **KISS.** Il target sono sistemisti/devops; il codice deve restare leggibile e
  modificabile anche da chi non è programmatore esperto. Preferisci sempre la
  soluzione più semplice e compatibile.
- **Opzioni lunghe ovunque.** In ogni chiamata a comandi esterni (`docker`, `sed`,
  `mkdir`, ecc.) usa la forma lunga dei flag dove esiste (`--detach` non `-d`,
  `--volume` non `-v`, `--interactive --tty` non `-it`, `--name`, `--env`,
  `--user`, ...). Rende il codice autoesplicativo. C'è un commento di testa che lo
  ricorda: mantienilo valido.
- **Un solo eseguibile.** Non introdurre file sorgente aggiuntivi né dipendenze.
- **Preflight obbligatorio.** Ogni sottocomando che usa Docker passa prima da
  `preflight_docker` (docker installato + daemon raggiungibile) e, tranne `init`,
  da `require_project` (`.env` con `AB_PROJECT=true`).

## Struttura di `ab`

1. Header + `set -euo pipefail` + costanti `DEFAULT_*`.
2. Helper: `die`, `warn`, `usage`, `preflight_docker`, `require_project`,
   `load_env`, `shell_quote`, `random_name`, `ask`, `ask_yes_no`.
3. Sottocomandi: `cmd_init`, `cmd_create`, `cmd_destroy`, `cmd_shell`, `cmd_root`
   (più gli helper `container_state`, `ensure_running`).
4. `main` con il dispatch `case` su `$1`, in fondo `main "$@"`.

`.env` è l'unica fonte di configurazione letta a runtime (`load_env` fa
`set -a; . ./.env; set +a`). `.env.example` è solo documentazione, mai letto.

## Decisioni di progetto importanti (contesto non ovvio)

- **Utente/gruppo nel container = quelli scelti in `.env`** (`USERNAME`/`GROUPNAME`),
  **non** l'utente di default dell'immagine. UID/GID sono sempre quelli dell'host
  (`id -u`/`id -g`), così l'ownership sui bind-mount è corretta senza `chown`.
- **Provisioning via modifica diretta di `/etc/passwd` e `/etc/group`** (in
  `cmd_create`, dentro un `docker exec ... sh -c '...'`). Scelto al posto di
  `useradd`/`adduser` per avere **un solo code path portabile** su ogni distro,
  Alpine inclusa (busybox non ha `useradd` senza `shadow`). Le `sed` rimuovono le
  righe in conflitto (per nome o per UID/GID) e poi si ricrea la riga corretta.
- **Shell di login dinamica.** In provisioning si imposta `bash` se presente
  nell'immagine, altrimenti `/bin/sh`. `cmd_shell`/`cmd_root` leggono il campo 7 di
  `/etc/passwd` con fallback `/bin/sh`: **mai `bash` hardcoded** (romperebbe Alpine).
- **`CONTAINER_CMD` non quotato nel `docker run`** (`... "$BASE_IMAGE" $CONTAINER_CMD`):
  lo split in parole è voluto (`sleep infinity` → due argomenti). Nel `.env` invece
  è quotato con apici singoli tramite `shell_quote`.
- **`random_name` in subshell con `set +o pipefail`**: senza, il `SIGPIPE` su `tr`
  quando `head` chiude la pipe farebbe fallire la funzione.
- **Guard root host:** `cmd_create` esce con errore se l'host è UID 0, perché UID 0
  entrerebbe in conflitto con `root` del container nel provisioning.

## Convenzioni quando modifichi

- I valori host passati al container vanno dati con `--env`, mai interpolati nel
  testo del comando, per evitare problemi di quoting/escaping.
- Messaggi utente in italiano. Errori con `die` (stderr, exit 1); avvisi non fatali
  con `warn`.
- I valori testuali scritti nel `.env` passano da `shell_quote`.

## Test (senza Docker)

Questo ambiente di sviluppo **non ha Docker**, quindi i percorsi che lo usano
(`create`/`destroy`/`shell`/`root`) non sono eseguibili qui. Cosa si può comunque
verificare:

- `bash -n ab` per la sintassi.
- `ab init` in una directory vuota temporanea (pipe degli input con `printf`),
  poi controllare `.env`/`.env.example` e il round-trip via sourcing.
- I percorsi d'errore (dir non vuota, comando fuori progetto, ecc.).
- La **logica di provisioning** simulando il corpo dello `sh -c` con `sh` su finti
  file `passwd`/`group` locali (scenari: overlap UID/GID, nessun overlap, solo
  root/Alpine, collisione di nome).

Collaudo end-to-end reale: solo su una macchina con Docker (vedi sezione "Verifica"
del piano e gli esempi nel `README.md`).

## Fuori scope (non implementare)

Networking/porte, env extra, volumi aggiuntivi oltre a `home/` e `bin/`, limiti di
risorse, multi-container, build di immagini, sottocomando `stop`.
