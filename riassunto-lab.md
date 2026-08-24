# Riassunto dei lab di stage — Simone D'Angelo

---

## Docker

### Lab 1 — Stack WordPress + MariaDB con Docker Compose
**Obiettivo:** prendere confidenza con Docker e Compose, la persistenza dei dati e la creazione di immagini.

**Svolgimento:**
- Stack base con `compose.yaml`: servizio `wordpress` (porta 8080) + `db` (MariaDB), con volumi nominati per la persistenza.
- **Step 4 — clonazione con dati ma volumi separati:** creata una seconda istanza (porta 8081) che parte con gli stessi dati ma su volumi propri, tramite dump del DB montato in `docker-entrypoint-initdb.d` e copia di `wp-content` via bind mount. Verificato l'isolamento: le modifiche sul sito 8081 non toccano l'8080.
- **Bonus — immagini custom da uno stack vivo:** dump del DB e copia di `wp-content` da un'istanza in esecuzione, `Dockerfile` custom per WordPress e MariaDB, deploy delle immagini custom senza volumi.

### Lab 2 — Monitoraggio con Grafana, Loki e Alloy
**Obiettivo:** aggiungere osservabilità (metriche/log) sopra lo stack del Lab 1.

**Svolgimento:**
- Grafana via Compose con bind mount (risolto un problema di permessi di scrittura che causava riavvii continui).
- Unito il Compose del Lab 1 nello stesso network per far dialogare i servizi.
- Configurata la **data source** Grafana → MariaDB usando il nome del servizio (`db:3306`, non `localhost`), e popolata la tabella dei post per avere dati da monitorare.
- Introdotti **Loki + Alloy**: Alloy raccoglie i log dei container via socket Docker, Loki li immagazzina; log visualizzati in Grafana.

### Lab 2.1 — Separazione ambienti prod/monitoring con reti isolate
**Obiettivo:** simulare la separazione realistica tra ambiente di produzione e ambiente di monitoraggio.

**Svolgimento:**
- Due reti: `wp_net` (produzione, isolata, definita solo nel Compose) e `log_net` (monitoraggio, creata a mano con `docker network create`).
- **Alloy come ponte** tra le due reti (deve stare in prod per l'accesso al socket dei container); il traffico va da prod verso monitoring e mai viceversa.
- Verifiche di isolamento con `ping`: WordPress non raggiunge Loki (reti diverse), Alloy raggiunge sia `db` sia Loki, Grafana non raggiunge `db`.
- Per far leggere a Grafana i dati del DB senza violare la separazione, creato un **utente MariaDB read-only** (solo `SELECT`) su una rete dedicata Grafana↔db — un modo per simulare un accesso in sola lettura in stile Prometheus. Testato: `SELECT` consentito, `DELETE` negato.

---

## Kubernetes

### Hello Minikube — Fondamenti di Kubernetes
**Obiettivo:** primi passi con Kubernetes in locale.

**Svolgimento:** installazione di minikube e kubectl; creazione di un deployment (`hello-node`); comandi base (`get pods/services/events`, `logs`, `config view`); esposizione con `Service` di tipo LoadBalancer e `minikube service`; addon `metrics-server` con `kubectl top`; dashboard; pulizia e stop/delete del cluster. Annotato il concetto di deployment (salute e scalabilità dei pod) e il warning sull'esposizione degli endpoint.

### Lab 1 — Cluster k3s reale (multi-nodo) + WordPress/MariaDB
**Obiettivo:** costruire un vero cluster k3s e portarci lo stack applicativo.

**Svolgimento:**
- **3 VM AlmaLinux** (1 server + 2 worker), stessa rete e hostname; aperte le porte necessarie con `firewall-cmd` (6443/tcp, 8472/udp, 10250/tcp).
- Installato k3s dal server con `--tls-san` (per l'accesso via VPN), poi i worker con `K3S_URL` + token. Risolti intoppi su IP sbagliato, PATH di AlmaLinux e kubeconfig.
- Portato WordPress + MariaDB su **manifest** (corrispondenza quasi 1:1 con Compose): `Secret` creato via kubectl (fuori dai file), `envFrom` vs `env` mappati, MariaDB in strategy `Recreate` (un solo scrittore, niente contesa del disco), differenza `port` vs `NodePort`.
- Prima introduzione a **Kustomize** (base + overlay/patch).

### Lab 1.1 — ArgoCD e GitOps
**Obiettivo:** gestire il deploy in modalità GitOps con ArgoCD.

**Svolgimento:**
- Installato ArgoCD sul cluster (namespace `argocd` + manifest ufficiale) ed esposta la GUI verso l'esterno (NodePort sul 443, firewall, password admin salvata).
- Creata un'`Application` dichiarativa che sincronizza l'overlay Kustomize `lab1.1/overlays/dev` dalla repo, con **syncPolicy automated (prune + selfHeal)** e `CreateNamespace`.
- **Prova del GitOps:** modificate le repliche da 2 a 3 nella patch, commit + push e resync → 3 pod WordPress senza alcun `kubectl apply` oltre a quello iniziale di ArgoCD.
- **Gestione secret:** tenuti fuori dalla repo sincronizzata (applicati a mano con `kubectl create secret --from-env-file`); esperimento separato con **git-crypt** (cifratura trasparente via `.gitattributes`, chiave esportata fuori dalla repo). Risolto un problema di PVC MariaDB "stantìo" con credenziali vecchie (delete di deploy + pvc).

### Lab 2 — Stack ELK + WordPress + Filebeat, con ILM
**Obiettivo:** logging centralizzato dello stack applicativo con Elasticsearch/Kibana/Logstash e gestione del ciclo di vita degli indici.

**Svolgimento:**
- Deploy di **Elasticsearch** (aggiustati heap e request/limit dopo un pending per memoria — regola "heap 50% del limite"), **Kibana** (NodePort) e **Logstash** (ClusterIP, config via ConfigMap coerente con la filosofia GitOps).
- WordPress + MariaDB + **Filebeat** (volume condiviso dei log Apache, Filebeat come root, `strict.perms: false`); generato traffico e verificati i log in Kibana (Discover + dashboard).
- Aggiunto **parsing** nella pipeline Logstash (grok sull'access.log).
- Implementato **ILM**: policy (hot con rollover per `max_docs`/`max_age`, warm con forcemerge, delete), index template, alias di rollover iniziale; Logstash scrive sull'alias. Verificati rollover e cancellazione con `_cat/indices`.
- Portato tutto su **Kustomize** (un kustomization per lo stack ELK e uno per WordPress, con `configMapGenerator`) e separato **dev/prod** con una patch sulle risorse di Elasticsearch. Sincronizzato con **ArgoCD** (riuso dell'Application del Lab 1.1): `Synced & Healthy`.

### Lab 3 — Due istanze WordPress con pipeline Logstash dedicate
**Obiettivo:** gestire più sorgenti di log distinte nello stesso stack ELK.

**Svolgimento:**
- Due istanze WordPress (**wp1** e **wp2**) che scrivono sullo stesso alias (stesse esigenze di volume/sicurezza).
- Logstash con un input **beats catchall** che instrada verso la pipeline dedicata all'istanza in base a un `field` impostato in `filebeat.yml` (da 1 a 3 pipeline gestite con un `if`).
- ILM come nel lab precedente (policy, template, alias, `replicas: 0` per avere lo stato `green`).
- **ArgoCD**: `Application` `lab3-elk` che sincronizza `lab3/overlays/dev` con automated prune + selfHeal + CreateNamespace.
- Generato traffico (7200 richieste totali) e verificata l'**aggregazione per istanza** (wp1: 3600, wp2: 3600) e il funzionamento di rollover e delete.

---

## Terraform + n8n

### Lab Terraform — Web server e2-micro su GCP tutto a codice
**Richiesta del tutor (dalla chat):** un lab Terraform "semplice": una compute **e2-micro** configurata per erogare pagine web, con **tutte** le configurazioni a codice (spec della VM, regole firewall, storage, utenti autorizzati, rete); **HTTPS senza costi** (self-signed via openssl); poi un **n8n on-prem F2** con una pipeline che genera contenuto via **LLM**, lo impacchetta in HTML e lo "spara" sulla micro con l'idea di "una pagina nuova al giorno", più una **repo che archivia** i contenuti precedenti.

**Svolgimento (parte Terraform):**
- Installati Terraform e gcloud su WSL, autenticate CLI e ADC, abilitata l'API Compute, generate le chiavi SSH.
- File `.tf`: provider google; variabili (quelle senza default in `terraform.tfvars`, con `tfvars.example` versionato); `main` con VPC + subnet /24, firewall (SSH solo dal proprio IP, HTTP/S da tutto il mondo), VM Debian in VPC, chiavi SSH via metadata, startup script; output con l'IP pubblico. Variabili sensibili e state fuori da Git.
- Flusso `init` → `plan` → `apply`. Risolto l'esaurimento di capacità e2-micro su us-central1 spostandosi su **us-west1-b** (sempre free tier).
- **startup script** della VM: legge l'URL repo dal metadata server, installa nginx/openssl/git, clona la repo, genera il **certificato self-signed** (IP pubblico come identità), configura nginx (80→301 verso 443, 443 con cert e web root), e installa un **cron di `git pull` ogni 5 minuti** → deploy in stile GitOps.

**Svolgimento (parte n8n + pipeline):**
- VM **AlmaLinux** on-prem su ESXi F2, n8n in Docker (host networking, bind mount `/opt/n8n/data`, encryption key fissa), porta 5678 aperta; sistemata l'**anomalia DNS di F2** (dnsmasq locale + resolv.conf) che rompeva la risoluzione dei nomi.
- **LLM:** Gemini non utilizzabile (l'account richiedeva il pre-payment, niente free tier reale; ChatGPT non offre più un tier free via API), quindi virato su **Ollama in locale** alla VM con `llama3.2:3b` (il modello 1B dava risposte sbagliate). Cambia solo l'URL del POST, niente autenticazione; da usare `127.0.0.1` e non `localhost` (che Node risolve in IPv6).
- **Workflow "film brutto del giorno":** (1) Schedule Trigger giornaliero alle 08:00; (2) HTTP Request a Ollama con prompt che restituisce un JSON; (3) nodo Code che parsa la risposta e genera l'HTML; (4) GitHub Get dell'`index.html` corrente da archiviare; (5) Code che decodifica il base64; (6) GitHub che archivia la pagina precedente con timestamp; (7) GitHub che aggiorna `live/index.html`. La micro fa il `git pull` e serve la nuova pagina; l'archivio conserva lo storico.
