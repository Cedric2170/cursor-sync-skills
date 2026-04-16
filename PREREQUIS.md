# Prerequis pour `cursorsync`

Ce document liste les prerequis necessaires avant d'utiliser les scripts
`install_host.sh`, `pullskills` et `pushskills`.

## Acces Git au depot source

- Avoir un compte autorise sur le depot Git cible.
- Avoir les droits en lecture sur le remote pour `pullskills`.
- Avoir les droits en ecriture sur le remote pour `pushskills`.
- Verifier que `origin` pointe vers le bon depot:

~~~bash
git -C "$HOME/.skills-sync" remote -v
~~~

## Cle SSH et authentification

- Disposer d'une cle SSH valide sur la machine (par exemple `~/.ssh/id_ed25519`).
- Ajouter la cle publique au compte Git (GitLab/GitHub selon le remote).
- Charger la cle privee dans un agent SSH actif.
- Verifier que l'authentification SSH fonctionne avant l'installation:

~~~bash
ssh -T git@gitlab.com
~~~

> NOTE: L'agent SSH doit etre actif dans la session shell qui execute les scripts.
> Sinon, `git clone`, `git pull` ou `git push` peuvent echouer.

## Agent SSH et persistance de la cle

- Demarrer un agent SSH si necessaire:

~~~bash
eval "$(ssh-agent -s)"
~~~

- Ajouter la cle privee a l'agent:

~~~bash
ssh-add "$HOME/.ssh/id_ed25519"
~~~

- Verifier que la cle est bien chargee:

~~~bash
ssh-add -l
~~~

## Arborescence et liens symboliques attendus

La logique actuelle est **symlink-only**:

- `~/.cursor/skills` -> `~/.skills-sync/skills`
- `~/.cursor/rules` -> `~/.skills-sync/roles`
- `~/.cursor/subagent` -> `~/.skills-sync/subagent`
- `~/.cursor/hooks` -> `~/.skills-sync/hooks`

Les scripts `pullskills` et `pushskills` verifient ces liens et echouent si un lien
est absent ou incorrect.

## Outils systeme requis

- `bash`
- `git`
- `rsync` (utilise par `install_host.sh` pour la migration initiale)
- `ssh`, `ssh-agent`, `ssh-add`

## Verification rapide avant execution

1. Tester l'acces SSH au remote.
2. Verifier que la cle est chargee dans l'agent (`ssh-add -l`).
3. Verifier que `~/.skills-sync` est un clone Git valide.
4. Verifier les symlinks sous `~/.cursor`.

Exemple:

~~~bash
test -d "$HOME/.skills-sync/.git" && echo "OK clone"
ls -l "$HOME/.cursor/skills" "$HOME/.cursor/rules" "$HOME/.cursor/subagent" "$HOME/.cursor/hooks"
~~~
