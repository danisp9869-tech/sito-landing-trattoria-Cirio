# Deploy su VPS (Nginx + SSL)

Questa cartella contiene tutto il necessario per pubblicare la landing su un
tuo server (VPS con Debian/Ubuntu + Nginx). Il **primo deploy** configura da
solo il virtual server Nginx e il certificato SSL Let's Encrypt; i deploy
successivi aggiornano solo i contenuti.

| File | A cosa serve |
|------|--------------|
| `provision-server.sh` | Gira sul VPS: installa Nginx/Certbot, crea il vhost e il certificato SSL. Idempotente. |
| `nginx-site.conf.template` | Modello di configurazione del virtual server Nginx. |
| `deploy.sh` | Deploy **manuale** dal tuo computer (rsync + provisioning). |
| `.env.example` | Modello dei valori per il deploy manuale (copialo in `.env`). |
| `../.github/workflows/deployvps.yml` | Deploy **automatico** ad ogni push su `main`. |

---

## Due modi per fare il deploy

### A) Automatico con GitHub Actions (consigliato)
Ad ogni `push` su `main` (o avvio manuale da **Actions → Run workflow**) il
sito viene pubblicato. Devi solo impostare i **Secrets** del repository una
volta sola:

**Settings → Secrets and variables → Actions → New repository secret**

| Secret | Esempio | Note |
|--------|---------|------|
| `VPS_HOST` | `123.45.67.89` | IP o hostname del server |
| `VPS_USER` | `deploy` | utente SSH (vedi prerequisiti) |
| `VPS_PORT` | `22` | opzionale, default 22 |
| `VPS_TARGET_DIR` | `/var/www/cirio` | cartella web servita da Nginx |
| `VPS_SSH_KEY` | *(chiave privata)* | contenuto della chiave SSH privata |
| `VPS_DOMAIN` | `anticatrattoriacirio.it` | dominio del sito |
| `VPS_EMAIL` | `info@…it` | email per Let's Encrypt |
| `VPS_INCLUDE_WWW` | `true` | opzionale, includi anche `www.` |

### B) Manuale dal tuo computer
```bash
cp deploy/.env.example deploy/.env
# compila deploy/.env con i tuoi dati
bash deploy/deploy.sh
```

---

## Prerequisiti sul VPS (una volta sola)

1. **Utente di deploy con SSH a chiave.** Crea l'utente e autorizza la tua
   chiave pubblica:
   ```bash
   sudo adduser --disabled-password deploy
   sudo mkdir -p /home/deploy/.ssh
   echo "LA-TUA-CHIAVE-PUBBLICA" | sudo tee /home/deploy/.ssh/authorized_keys
   sudo chown -R deploy:deploy /home/deploy/.ssh
   sudo chmod 700 /home/deploy/.ssh && sudo chmod 600 /home/deploy/.ssh/authorized_keys
   ```

2. **Sudo senza password** per l'utente di deploy (serve a installare Nginx,
   creare il vhost e lanciare Certbot in automatico):
   ```bash
   echo "deploy ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/deploy
   sudo chmod 440 /etc/sudoers.d/deploy
   ```
   > In alternativa, per restringere: concedi NOPASSWD solo su
   > `apt-get`, `nginx`, `systemctl`, `certbot`, `mkdir`, `cp`, `ln`, `rm`, `tee`.

3. **DNS.** Il record `A` del dominio (e di `www` se usi `VPS_INCLUDE_WWW=true`)
   deve puntare all'IP del VPS **prima** del primo deploy, altrimenti Certbot
   non riesce a emettere il certificato. Se il DNS non è ancora pronto il sito
   parte comunque in HTTP e l'SSL viene richiesto al deploy successivo.

4. **Porte 80 e 443 aperte** nel firewall del VPS.

---

## Come funziona l'automazione (primo deploy vs successivi)

`provision-server.sh` è **idempotente**:

- **Primo deploy** → installa Nginx e Certbot se mancano, crea
  `/etc/nginx/sites-available/DOMINIO.conf`, lo abilita, disattiva il default,
  poi lancia `certbot --nginx … --redirect` che ottiene il certificato,
  aggiunge il blocco HTTPS (443) e forza il redirect da HTTP.
- **Deploy successivi** → rileva che vhost e certificato esistono già, non
  tocca la configurazione e si limita a ricaricare Nginx. Il rinnovo del
  certificato è gestito in automatico dal timer di Certbot.

Il contenuto del sito viaggia sempre via `rsync --delete`, quindi il server
resta allineato al repository.
