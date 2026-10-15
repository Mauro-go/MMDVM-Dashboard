# MMDVM Dashboard — Guida in italiano

Dashboard web indipendente per ripetitori MMDVM, con attività radio, informazioni del ripetitore, statistiche del sistema e pagina di amministrazione protetta. Interfaccia in **italiano e inglese**.

> **Stato: versione preliminare, non ancora collaudata su una Debian pulita.** Prima di installarla su un ripetitore in servizio, provarla su una macchina di test. Nel repository non devono essere pubblicati configurazioni personali, fotografie, token, password o backup.

English instructions: [README.md](README.md).

## Sicurezza e funzionamento

La dashboard **legge** la configurazione e i log MMDVM. L'installer **non modifica** `MMDVM.ini`, non ferma né riavvia `MMDVMHost` e non interviene su `DMRGateway`, `YSFGateway` o altri gateway radio. Utilizza un backend Flask su `127.0.0.1:8088` e un VirtualHost Apache dedicato. Non sovrascrive `/var/www/html/index.html`.

L'installer è destinato a **nuove installazioni**. Se trova `/opt/mmdvm-dashboard`, `/var/lib/mmdvm-dashboard`, un servizio `mmdvm-dashboard.service` oppure il proprio file VirtualHost Apache, **si ferma senza sovrascrivere**. Per sostituire un'installazione con gli stessi nomi serve una migrazione manuale specifica.

## Requisiti

- Debian **11, 12 o 13** con systemd e privilegi root/sudo. Sono le versioni previste, **non ancora tutte verificate**.
- Un nome DNS pubblico che punti al server e porte **TCP 80/443** raggiungibili per Let's Encrypt. Per ora l'installer non supporta installazioni solo LAN, certificati autofirmati o reverse proxy esterni.
- Porta locale **8088** libera e nessun VirtualHost Apache che utilizzi già il dominio scelto.
- Permessi di **lettura** sui log MMDVM, su `MMDVM.ini` e sugli eventuali file DMR ID/TalkGroup. L'installer non modifica automaticamente i permessi dei log.
- Tutti i file del progetto, compreso `config/dashboard.ini.example`.

I pacchetti vengono installati dai repository Debian: Apache, Certbot, Python 3, Flask, Werkzeug, psutil, curl, OpenSSL e utilità correlate. Non è necessario usare `pip` globalmente. Il file `requirements.txt` documenta le dipendenze Python.

## Installazione (consigliata prima su una macchina di prova)

```bash
sudo apt-get update
sudo apt-get install -y git
sudo git clone https://github.com/Mauro-go/MMDVM-Dashboard.git /opt/mmdvm-dashboard-source
cd /opt/mmdvm-dashboard-source
sudo bash install.sh
```

**Questi comandi funzioneranno soltanto dopo che avremo pubblicato tutti i file nel repository GitHub.** Non eseguire l'installer su una macchina dove la dashboard attuale utilizza già `/opt/mmdvm-dashboard` o `mmdvm-dashboard.service`.

L'installer richiede il dominio pubblico, l'email per Let's Encrypt e una conferma esplicita. Installa le dipendenze, crea l'utente di servizio `mmdvm-dashboard`, copia i file, crea la directory privata, genera token iniziale e segreto di sessione, avvia il backend, configura Apache/HTTPS e verifica le API.

## Primo accesso: token e pagina Admin

Al termine dell’installazione, `install.sh` mostra sul terminale il **token di attivazione monouso**. Se non lo hai copiato, prima della creazione dell’amministratore puoi recuperarlo **direttamente sul server**, come `root`:

```bash
sudo cat /var/lib/mmdvm-dashboard/setup-token
```

**Non pubblicare il token**, non inserirlo nel repository GitHub e non inviarlo in chat. Il file è leggibile soltanto dagli utenti autorizzati sul server e viene eliminato dopo la creazione dell’account amministratore.

Apri nel browser la dashboard all’indirizzo `https://TUO-DOMINIO/`. La pagina di amministrazione è prevista all’indirizzo **`https://TUO-DOMINIO/api/admin/page`**: **verificare questo percorso nel codice `backend/admin_api.py` prima della pubblicazione**, perché la distribuzione deve includere esplicitamente la route che serve `admin/admin.html`.

Al primo accesso alla pagina Admin, inserisci il token, scegli **nome utente** e **password**, conferma la password e premi **Crea amministratore**. Successivamente effettua l’accesso con le credenziali appena create. Nella pagina Admin configura i percorsi di `MMDVM.ini`, dei log e degli altri file necessari.

Se il token è già stato utilizzato, il file `setup-token` non esiste più: è il comportamento previsto. Non rigenerarlo per sostituire una password dimenticata; il recupero delle credenziali richiede una procedura separata e sicura.

## Migrazione dalla vecchia dashboard

Due dashboard **possono convivere** se usano nomi di servizio, porte backend e indirizzi web differenti. Il nostro installer utilizza `mmdvm-dashboard.service` e la porta 8088, quindi **non rinomina e non sovrascrive automaticamente** un'installazione che li utilizza già.

L'installer verifica la presenza di `logtailer.service`. **Soltanto se confermi esplicitamente che appartiene esclusivamente alla vecchia dashboard** puoi scegliere di fermarlo. Lo script attende che la nuova dashboard abbia superato i controlli HTTPS/API, poi lo ferma **solo se attivo** e ne disabilita l'avvio automatico **solo se abilitato**. Non cancella il servizio né i suoi file. Se un controllo successivo fallisce, tenta di ripristinarne lo stato e riavviarlo. Non selezionare questa opzione se `logtailer` è condiviso con altri programmi.

Altri servizi della vecchia dashboard **non vengono fermati automaticamente**. Per controllare la propria installazione:

```bash
systemctl list-units --type=service --all | grep -Ei 'dashboard|logtailer'
systemctl status logtailer.service
sudo ss -ltnp
```

### Se esiste già `index.html`

Se trova `/var/www/html/index.html`, l'installer **avvisa e lo lascia intatto**. Non crea un backup perché non modifica quel file. Controlla inoltre che il dominio scelto non sia già presente nei VirtualHost Apache e non sovrascrive il proprio file VirtualHost. La configurazione Apache esistente viene mantenuta, ma l'attivazione dei moduli e il reload di Apache interessano il server web: prima di installare su un server condiviso è prudente eseguire un backup della configurazione Apache.

## Pagina Admin e immagini

Dalla pagina Admin si possono configurare, secondo la versione installata, titolo, dati del ripetitore, hardware, organizzazione, collegamenti, **percorsi** delle immagini e percorsi MMDVM. Le modalità radio sono lette dalla configurazione MMDVM e mostrate in sola lettura.

**Il caricamento delle immagini dal browser non è ancora previsto.** Copia le immagini personali in `frontend/images/` con permessi appropriati, poi inserisci percorsi relativi come `images/banner.jpg`. L'installer non include immagini personali.

### Permessi

Il codice applicativo appartiene a `root`; `config/dashboard.ini` e `/var/lib/mmdvm-dashboard/` sono scrivibili dall'utente dedicato. I log e i file MMDVM saranno leggibili soltanto se i permessi Linux lo consentono. Concedi **solo i permessi di lettura necessari**: non eseguire la dashboard come root e non rendere pubbliche credenziali o log.

## Gestione servizi e diagnostica

```bash
sudo systemctl status mmdvm-dashboard.service
sudo journalctl -u mmdvm-dashboard.service -n 100 --no-pager
sudo apache2ctl configtest
sudo systemctl status apache2
curl -fsS http://127.0.0.1:8088/api/status
```

Se HTTPS non funziona, controlla DNS, porta 80 e Certbot. Se mancano i dati radio, verifica i percorsi e i permessi di lettura. Non riavviare i servizi radio per risolvere problemi della dashboard.

## Errori, ripristino e disinstallazione

L'installer **non è completamente transazionale**. Un errore prima della migrazione lascia in funzione il vecchio servizio, ma può lasciare pacchetti, file, unità systemd, configurazioni Apache o certificati creati durante il tentativo. Controllali prima di riprovare. Se aveva fermato un `logtailer.service` confermato e il controllo successivo fallisce, tenta di riavviarlo; verifica manualmente lo stato.

Per tornare alla vecchia dashboard, verifica prima il relativo servizio e la configurazione web, poi riabilita e avvia esplicitamente **solo il servizio corretto**. Non cancellare indiscriminatamente `/var/www/html`, `/etc/apache2`, le directory MMDVM o i servizi radio. **Non è ancora disponibile un disinstallatore automatico**: prima di eliminare file, esegui backup e controlla quali risorse sono condivise.

## Privacy e pubblicazione su GitHub

Non pubblicare `config/dashboard.ini`, `/var/lib/mmdvm-dashboard/`, password, segreti di sessione, token, immagini personali, log, database o file `*.bak*`. Prima di ogni pubblicazione controlla `git status` e `git diff --cached`. Nel repository deve esserci soltanto `config/dashboard.ini.example`, con valori generici.

## Autore e licenza

MMDVM Dashboard by **IV3SCP** · [GitHub](https://github.com/Mauro-go/MMDVM-Dashboard). La licenza del progetto va definita prima della pubblicazione.

## Opzione sperimentale: HTTP solo nella rete locale

`install.sh` rimane dedicato all'installazione **HTTPS** con dominio pubblico e Let's Encrypt. Dopo aver completato con successo l'installazione HTTPS, puoi usare lo script separato `switch-http.sh`:

```bash
sudo bash switch-http.sh http
```

Lo script chiede conferma, salva copie originali di `backend/admin_api.py` e del VirtualHost Apache in `/var/lib/mmdvm-dashboard-http-switch/`, limita l'accesso HTTP ai client IPv4 privati e loopback e adatta il cookie e il controllo dell'origine per l'Admin. La pagina Admin rimane al percorso `/api/admin/page`, ma in HTTP. Il server deve essere raggiungibile sul VirtualHost corretto; in presenza di più siti Apache l'accesso tramite solo IP potrebbe richiedere una configurazione aggiuntiva.

Per **tornare alla configurazione HTTPS precedente**, esegui:

```bash
sudo bash switch-http.sh https
```

**Attenzione:** HTTP non cifra password né sessioni. Non pubblicare la porta 80 su Internet e non utilizzare HTTP su reti non affidabili. I controlli Apache non sostituiscono firewall e regole del router. Questa modalità non è ancora collaudata su una Debian pulita: provarla prima su una macchina di test. Non usare lo script per installare da zero: richiede una precedente installazione HTTPS funzionante. Non cancellare manualmente la directory di backup prima del ripristino.
