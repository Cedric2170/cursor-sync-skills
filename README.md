# Cursor Skills Sync

Synchronisez facilement vos skills Cursor entre vos hosts avec votre depot Git.

---

## Ce que vous devez preparer avant de commencer

- Un compte Git (GitHub/GitLab) avec acces SSH.
- Un **repo personnel pour vos skills** (obligatoire avant l'installation).
- Une cle SSH ajoutee a votre compte Git.
- La cle chargee dans un agent SSH actif (`ssh-add -l`).
- `git` et `bash` installes sur votre machine.

---

## Installation rapide

### 1) Creer votre repo personnel de skills

~~~bash
# Exemple GitHub
# 1. Creez un repo vide (ex: mes-cursor-skills)
# 2. Copiez son URL SSH
#    git@github.com:VOTRE-USER/mes-cursor-skills.git
~~~

### 2) Cloner ce projet

~~~bash
git clone git@github.com:Cedric2170/cursor-sync-skills.git
cd cursor-sync-skills/cursorsync
~~~

### 3) Configurer le fichier `.env`

~~~bash
cp .env.example .env
~~~

Puis editez `.env` et modifiez au minimum:

- `SKILLS_ORIGIN_URL` avec l'URL SSH de **votre repo personnel**.

Exemple:

~~~bash
SKILLS_ORIGIN_URL="git@github.com:VOTRE-USER/mes-cursor-skills.git"
~~~

### 4) Lancer l'installation

~~~bash
./install_host.sh
~~~

### 5) Recharger votre shell

Le script ajoute les alias `pullskills` et `pushskills`.


Si vous utilisez Zshrc:

~~~bash
source ~/.zshrc
~~~

Si vous utilisez Bash:

~~~bash
source ~/.bashrc
~~~

### 6) Verifier que tout est pret

~~~bash
pullskills
~~~

Si la commande passe, votre installation est operationnelle.

---

## Utilisation au quotidien

- Recuperer les mises a jour:

~~~bash
pullskills
~~~

- Envoyer vos changements:

~~~bash
pushskills
~~~

---

## Besoin d'aide

Si l'installation echoue:

- verifiez votre acces SSH au remote;
- verifiez que `SKILLS_ORIGIN_URL` dans `.env` pointe vers votre repo personnel;
- relancez ensuite `./install_host.sh`.

---

## Auteur

Baertschi Cedric - [github.com/Cedric2170](https://github.com/Cedric2170/)
