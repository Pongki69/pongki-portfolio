# Alfonso A. Panisales — Developer Portfolio

A personal portfolio showcasing selected web development projects, skills, and contact information.

## Run locally

Open `index.html` in a browser. The site is built with HTML, CSS, and JavaScript and does not require a build step.

## Manage portfolio projects

Run `start-repo-manager.bat` on Windows to open the local project manager. It reads your public, non-fork repositories from GitHub and gives every project the same editor for its title, description, icon, category, links, searchable language badges, project details, overview, workflows, status steps, notes, screenshot gallery, and optional live preview. Toggle optional sections on or off per project. Choose **Save & push** to publish the portfolio data and selected icon images to `main`.

The manager needs Node.js and a Git setup that can push to this repository. It runs on `127.0.0.1` and is excluded from Vercel deployments. Visitors only read the public project list; the portfolio has no login or write endpoint.

## Pages

- `index.html` — portfolio home page
- `atheria.html` — interactive Atheria prototype
- `portfolio-projects.json` — public portfolio project details, sections, languages, and statuses
- `portfolio-project-renderer.js` — renders the saved project cards on the portfolio
- `assets/project-icons/` — uploaded project icon images
- `repo-manager/` — local project management app

