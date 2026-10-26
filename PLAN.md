# Plan: staging, production and a deploy pipeline on k3s

**Goal:** test a new version of Kanso in **staging** with a few chosen people, while
**production** keeps running the current version. When staging looks good, **promote**
the same version to production. Then let **GitHub Actions** do these steps, so we can
see the workflow as a picture.

**Rules we keep**

- k3s only.
- The pipeline pushes changes into the cluster. Nothing inside the cluster watches
  a repo (no GitOps).
- Promote means: take the exact image that was tested in staging and use it in
  production. We never rebuild for production.

**Where we are today**

- k3s runs in one Docker container (`k3s/docker-compose.yml`).
- Kanso runs in one namespace called `kanso`, at http://kanso.localhost:8081.
- `k3s/deploy.sh` builds the image, loads it into k3s and updates the site.
- Rolling update and rollback have been tested.

---

## Phase 1: Staging and production side by side

Status: done.

Everything stays on this machine. No GitHub yet.

**What we build**

1. **Show the version on the page.** The image gets a version number at build time.
   The page footer shows it, so you can see at a glance which version you are on.
2. **Two namespaces instead of one.**
   - `kanso-prod` at http://kanso.localhost:8081
   - `kanso-staging` at http://staging.kanso.localhost:8081
3. **One set of files, two small differences.** The shared setup lives in
   `k3s/manifests/base/`. Staging and production each get a short file that only
   says what is different (name, web address, number of copies). kubectl can join
   them by itself (`kubectl apply -k`), so we need no extra tools.
4. **Three simple scripts:**
   - `deploy.sh <tag>` builds a new version and puts it on **staging only**.
   - `promote.sh` reads which image staging runs and puts **that same image** on production.
   - `rollback.sh <staging|prod>` goes back to the previous version.
5. **(Optional) Lock staging.** A username and password in front of staging, so only
   the chosen people can open it.

**Done when**

- Staging shows version 1.1 while production still shows version 1.0.
- After `promote.sh`, production shows 1.1.
- `rollback.sh prod` brings production back to 1.0 without touching staging.

---

## Phase 2: Keep images in a registry

So far we load images straight into k3s. A pipeline cannot do that. It needs a
shared place to put images, called a registry.

**What we build**

1. Use **GitHub Container Registry (GHCR)**: `ghcr.io/thomasjmtan/kanso-web`.
2. Name each image after the **git commit** it came from. This tells you exactly
   which code is running.
3. The repo looks private, so the cluster needs a **pull secret** (a read-only
   token) to download images. It lives only in the cluster, never in git.
4. Production uses the image's **digest** (its fingerprint), not just its name. A
   name can be pointed at a different image later. A digest cannot.

**Done when**

- Both namespaces pull their images from GHCR.
- `promote.sh` copies the digest from staging to production.

---

## Phase 3: A limited account for the pipeline

Status: done.

The Headlamp login can do anything in the cluster. The pipeline must not have that
much power.

**What we build**

1. A service account called `deployer`.
2. It can only **read and update Deployments** (and read pods to watch progress) in
   `kanso-staging` and `kanso-prod`. Nothing else, nowhere else.
3. A kubeconfig file for `deployer`. It is a secret: we keep it out of git and only
   give it to the runner.

**Done when**

- `deployer` can update Kanso but gets "forbidden" if it tries anything else
  (for example, deleting a namespace).

---

## Phase 4: A GitHub runner on this machine

GitHub's own machines cannot reach a cluster on your PC. So we run a small GitHub
program here, called a **self-hosted runner**. It only makes outgoing connections
to GitHub; nothing on your PC is opened to the internet.

**What we build**

1. Install the runner on this PC and connect it to the repo.
2. Give it a label (for example `k3s-local`) so only our deploy jobs use it.

**Watch out**

- A self-hosted runner runs code from the repo on your PC. Keep the repo
  **private**, or make sure strangers' pull requests can never start a job.

**Done when**

- The runner shows as "Idle" in the repo's settings.

---

## Phase 5: The pipeline

**What we build**

1. **Main pipeline** (`.github/workflows/deploy.yml`), runs on every push to `main`:
   1. **Build:** build the image and push it to GHCR (tag = commit).
   2. **Deploy to staging:** update `kanso-staging` and wait until it is healthy.
   3. **Wait for approval:** a person clicks "Approve" in GitHub.
   4. **Deploy to production:** put the **same digest** on `kanso-prod` and wait
      until it is healthy.
2. **Rollback pipeline** (`.github/workflows/rollback.yml`): a button in GitHub.
   You pick staging or production, and it runs a rollback.
3. In GitHub, two **Environments**: `staging` and `production`. Production has
   **required reviewers**, which creates the approval step.

**Watch out**

- On a private repo, required reviewers may need a paid GitHub plan. If it is not
  available, the production step becomes a separate button you press by hand.
  The result is the same, but the picture is less tidy.

**Done when**

- A push to `main` shows the full chain in the Actions tab:
  build → staging → waiting → production.
- Staging updates by itself. Production only updates after approval.
- The rollback button works for each environment.

---

## Phase 6 (optional): Install without internet

Only needed if this later moves to a machine with no internet. We write down how to
copy the k3s program and its images onto the machine by hand, and how to load our
own image the same way.

---

## Decisions needed

| Question | Suggestion |
|---|---|
| Which registry? | GHCR |
| Keep the GitHub repo private? | Yes, because of the self-hosted runner |
| Who approves production deploys? | You (thomasjmtan) |
| Lock staging with a password (Phase 1, step 5)? | Yes, a simple one |
