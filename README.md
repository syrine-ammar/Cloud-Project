# ☁️ Cloud Project — Full-Stack AWS Deployment

> Déploiement d'une application Full-Stack (Node.js + Angular + MySQL) sur AWS avec Terraform (Infrastructure as Code)

---

## 🏗️ Architecture

```
Internet
   │
   ├──► Frontend EC2 (public subnet AZ-A)
   │       └── Nginx sert les fichiers Angular (dist/)
   │               └── appelle l'ALB pour les données API
   │
   └──► ALB — Application Load Balancer (public subnets AZ-A + AZ-B)
               └── Target Group (health check GET /health → 200)
                       │
                       ├── Backend EC2 AZ-A (private subnet)  ┐
                       │       └── Node.js · port 3000         ├── Auto Scaling Group
                       └── Backend EC2 AZ-B (private subnet)  ┘  min 2 · max 4
                                └── Node.js · port 3000
                                        └── RDS MySQL 8.0 (private subnets)
```

---

## 📁 Structure du projet

```
CloudProject/
├── backend/                    # API Node.js + Express
│   ├── index.js                # Point d'entrée — routes CRUD + /health
│   ├── package.json
│   ├── .env                    # Variables locales (jamais pushé)
│   ├── .gitignore
│   └── data/                   # Fallback JSON storage
│
├── client/                     # Frontend Angular 19
│   ├── src/
│   │   ├── app/                # Composants Angular
│   │   └── environments/
│   │       ├── environment.ts          # Config locale (localhost:3000)
│   │       └── environment.prod.ts     # Config AWS (ALB_DNS_PLACEHOLDER)
│   ├── dist/                   # Build compilé (pushé sur GitHub)
│   └── .gitignore              # Ne pas ignorer dist/
│
└── terraform/                  # Infrastructure as Code
    ├── main.tf                 # Toutes les ressources AWS
    ├── variables.tf            # Déclaration des variables
    ├── outputs.tf              # URLs affichées après apply
    ├── terraform.tfvars        # Valeurs secrètes (jamais pushé)
    ├── userdata_backend.sh     # Script démarrage EC2 backend
    ├── userdata_frontend.sh    # Script démarrage EC2 frontend
    └── .gitignore              # Ignore tfvars, .terraform/, tfstate
```

---

## ⚙️ Stack technique

| Couche | Technologie |
|---|---|
| Frontend | Angular 19 · Nginx |
| Backend | Node.js · Express · mysql2 |
| Base de données | Amazon RDS MySQL 8.0 · db.t3.micro |
| Infrastructure | Terraform ~> 4.67 · AWS us-east-1 |
| Serveur | Amazon Linux 2023 · t2.micro |
| Load Balancer | AWS ALB · Target Group · health check /health |
| Auto Scaling | ASG min 2 · max 4 · CPU tracking 70% |

---

## 🌐 Composants AWS

### Réseau — VPC (10.0.0.0/16)

| Subnet | CIDR | AZ | Contenu |
|---|---|---|---|
| public-a | 10.0.1.0/24 | us-east-1a | Frontend EC2, Internet Gateway, NAT Gateway |
| public-b | 10.0.2.0/24 | us-east-1b | ALB (span AZ-A + AZ-B) |
| private-a | 10.0.3.0/24 | us-east-1a | Backend EC2 (ASG) |
| private-b | 10.0.4.0/24 | us-east-1b | Backend EC2 (ASG) + RDS MySQL |

### Security Groups

| Security Group | Inbound | Outbound |
|---|---|---|
| `alb-sg` | port 80 ← 0.0.0.0/0 | tout → 0.0.0.0/0 |
| `backend-sg` | port 3000 ← alb-sg seulement | tout → 0.0.0.0/0 |
| `rds-sg` | port 3306 ← backend-sg seulement | tout → 0.0.0.0/0 |
| `frontend-sg` | port 80 ← 0.0.0.0/0 · port 22 ← 0.0.0.0/0 | tout → 0.0.0.0/0 |

---

## 🚀 Déploiement

### Prérequis

- [Terraform](https://developer.hashicorp.com/terraform/install) installé
- Compte AWS Academy (Vocareum) avec credentials actifs
- Node.js + Angular CLI installés localement
- Dépôt GitHub avec `dist/` du client buildé

### 1 — Builder le frontend localement

```bash
cd client
npm install
npx ng build --configuration=production
cd ..
git add client/dist
git commit -m "production build"
git push origin main
```

### 2 — Créer terraform.tfvars

```bash
cd terraform
```

Créer le fichier `terraform.tfvars` (ne jamais committer) :

```hcl
repo_url    = "https://github.com/YOURNAME/CloudProject.git"
db_password = "VotreMotDePasse123!"
db_username = "appuser"
db_name     = "appdb"
```

### 3 — Configurer les credentials AWS (Vocareum)

```powershell
$env:AWS_ACCESS_KEY_ID="..."
$env:AWS_SECRET_ACCESS_KEY="..."
$env:AWS_SESSION_TOKEN="..."
```

### 4 — Déployer

```bash
cd terraform
terraform init      # une seule fois (télécharge le provider AWS)
terraform plan      # prévisualiser les ressources
terraform apply     # déployer (~12 minutes, RDS est lent)
```

### 5 — Outputs après apply

```
frontend_url       = "http://<ip-publique>"
alb_dns            = "http://project-alb-xxxx.us-east-1.elb.amazonaws.com"
health_check_url   = "http://project-alb-xxxx.us-east-1.elb.amazonaws.com/health"
rds_endpoint       = "project-mysql.xxxx.us-east-1.rds.amazonaws.com"
backend_asg_name   = "project-backend-asg"
```

### 6 — Nettoyer (obligatoire avant fin de session Vocareum)

```bash
terraform destroy
```

---

## 🔌 API Endpoints

| Méthode | Endpoint | Description |
|---|---|---|
| GET | `/health` | Health check ALB → retourne `{"status":"ok"}` |
| GET | `/server-info` | Instance ID + AZ (démo load balancing) |
| GET | `/api/users` | Liste tous les utilisateurs |
| GET | `/api/users/:id` | Récupère un utilisateur par ID |
| POST | `/api/users` | Crée un utilisateur `{name, email}` |
| PUT | `/api/users/:id` | Met à jour un utilisateur |
| DELETE | `/api/users/:id` | Supprime un utilisateur |

---

## 🔒 Sécurité

- Les mots de passe DB sont passés via **variables d'environnement** (fichier `.env` sur EC2, jamais dans le code)
- `terraform.tfvars` est dans `.gitignore` — les secrets ne sont jamais pushés
- RDS a `publicly_accessible = false` — inaccessible depuis internet
- Le backend EC2 est dans un **subnet privé** — jamais directement accessible
- Les Security Groups utilisent des **références SG** (pas des plages IP) pour les règles internes

---

## 🧪 Vérifications

```bash
# Backend health
curl http://<alb-dns>/health
# → {"status":"ok"}

# Load balancing (instanceId change à chaque refresh)
curl http://<alb-dns>/server-info

# API utilisateurs
curl http://<alb-dns>/api/users
```

---



## 📝 Notes Terraform

- Provider version `~> 4.67` obligatoire sur Vocareum (v5 bloqué par permissions S3)
- `LabInstanceProfile` utilisé à la place d'un rôle IAM custom (role IAM non autorisé sur Vocareum)
- `terraform init` uniquement à la première utilisation ou après changement de provider
- Les scripts User Data utilisent `templatefile()` pour injecter les variables sans problème d'indentation

---

*Projet Cloud 2025/2026*
