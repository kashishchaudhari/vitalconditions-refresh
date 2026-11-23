# Deployment

The pipeline needs R and runs for several minutes, so it runs on **GitHub Actions**, not on Vercel. Actions refreshes the data, validates it, renders the Quarto site, and publishes it to **GitHub Pages** only if validation passed. Vercel is an optional second host for the same static files.

```
GitHub Actions (.github/workflows/refresh.yml)
  build job:  renv restore -> tests -> tar_make() (pull, build, VALIDATE, render)
              └─ any validation failure stops here; nothing is published
  deploy-pages job:   only on manual or scheduled runs, only if build passed
                      and repo variable ENABLE_PAGES = true
  deploy-vercel job:  same, and only if repo variable ENABLE_VERCEL = true
```

Triggers:

| Trigger | What happens |
|---|---|
| **Manual** (Actions tab, "Run workflow") | Full refresh, validate, deploy |
| **Monthly schedule** (06:00 UTC on the 5th) | Same. Picks up new Census releases automatically. |
| **Pull request** | Tests and full validation, **no deploy** |

## One-time setup

### 1. Census API key (required)

Repo **Settings → Secrets and variables → Actions → New repository secret**:

- Name: `CENSUS_API_KEY`
- Value: your key from https://api.census.gov/data/key_signup.html

It is stored encrypted, and GitHub hides it in logs. Pull requests from forks do not receive secrets, so for those the workflow runs only the offline tests.

### 2. GitHub Pages (optional, off by default; the live site is on Vercel)

**Settings → Pages → Build and deployment → Source: GitHub Actions**, then add a repository variable `ENABLE_PAGES` = `true`. The site will be at `https://<user>.github.io/vitalconditions-refresh/`.

### 3. Vercel (optional, off by default)

1. Create a Vercel project (no framework, no build command). Copy its IDs from `.vercel/project.json` after `vercel link`, or from the project's settings.
2. Add repository **secrets** `VERCEL_TOKEN`, `VERCEL_ORG_ID` and `VERCEL_PROJECT_ID`.
3. Add a repository **variable** (not a secret) `ENABLE_VERCEL` = `true`.

The job deploys the already-built `_site/` folder as static files (`vercel.json` sets the output directory). No serverless functions are used.

### Vercel from your own machine (how the live site is deployed now)

The live site is at https://vitalconditions-refresh.vercel.app (Vercel project `vitalconditions-refresh`). To update it after a local `targets::tar_make()`:

```powershell
npx vercel deploy --prod --yes
```

This uploads only the built `_site/` folder (`.vercelignore`) as static files. `vercel.json` turns off Vercel's own Git builds, because Vercel cannot run the R pipeline. The first time on a new machine, run `npx vercel login` and `npx vercel link --project vitalconditions-refresh`.

## Running a refresh manually

**Actions → Refresh, validate and publish → Run workflow** on `main`. When it finishes:

- Green: the site is updated, and its footer shows the new run date, commit and "validation: passed".
- Red at the build step: open the run, download the `validation-report` artifact, and see which check failed. The old site stays up.

## Caches

The workflow caches the renv package library (`r-lib/actions/setup-renv`) and the Census API cache (`data/cache/`, keyed by month), so routine runs re-download only what changed. To force a full re-download, delete the cache under **Actions → Caches**.

## Running locally instead

```r
renv::restore()
targets::tar_make()   # writes outputs/, reports/refresh_summary.html and _site/
```

Then open `_site/index.html`.
