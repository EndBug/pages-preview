# Pages Preview

[![All Contributors](https://img.shields.io/github/all-contributors/EndBug/pages-preview)](#contributors-)

## Table of contents

- [What does it do?](#what-does-it-do)
- [Setup](#faqs)
- [Inputs](#inputs)
- [Contributors](#contributors-)

## What does it do?

A lot of third-party services allow you create preview deployments of branches and pull requests, so that you can use them to review and test your changes. This action allows you to do the same thing, but directly with GitHub Pages.  

In particular, this action deploys your website to a different repo, which will contain the previews of all the repos you choose to use this on. 

If you're interested in the logic behind this action, you can check out the [flow diagram](docs/flow_diagram.md).

## Setup

### Preview repo

1. Create a new repo that will host your previews.

2. Make sure that this repo has two branches: `main` and `gh-pages` (you can also choose different names).
    - `main` should be your default branch, and it will only hold a workflow (and any additional files you want to add, liKE a README, a license, etc.). 
    - `gh-pages` will be the branch that will contain the actual previews, and it should be empty.

3. Create a new file in the `main` branch, and name it `.github/workflows/preview.yml`. Then copy the contents of [`dependents/preview-repo.yml`](dependents/preview_repo.yml) into it.  
  You shouldn't need to change anything in this file, the config options will all be in the source repo workflow.  
  This file might need to be updated if you update the action to a different major version.

4. Go into your repo settings, in the Pages tab ([Settings > Pages](../../settings/pages)) and set "GitHub Actions" as the source.
