# Alfonso A. Panisales — Developer Portfolio

A personal portfolio showcasing selected web development projects, skills, and contact information.

## Run locally

Open `index.html` in a browser. The site is built with HTML, CSS, and JavaScript and does not require a build step.

## Manage portfolio projects

Run `start-repo-manager.bat` on Windows to open the local project manager. It reads your public, non-fork repositories from GitHub and lets you show each one under **Live**, **In progress**, **More GitHub projects**, or hide it. Choose a live URL when a project has a demo, then select **Save & push** to update `portfolio-projects.json`, commit it, and push it to `main`.

The manager needs Node.js and a Git setup that can push to this repository. It runs on `127.0.0.1` and is excluded from Vercel deployments. Visitors only read the public project list; the portfolio has no login or write endpoint.

## Pages

- `index.html` — portfolio home page
- `atheria.html` — interactive Atheria prototype
- `portfolio-projects.json` — public portfolio project list and statuses
- `repo-manager/` — local project management app

