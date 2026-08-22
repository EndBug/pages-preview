# Pages Preview

## Table of contents

- [What does it do?](#what-does-it-do)
- [Setup](#setup)
- [Inputs](#inputs)

## What does it do?

A lot of third-party services allow you create preview deployments of branches and pull requests, so that you can use them to review and test your changes. This action allows you to do the same thing, but directly with GitHub Pages.  

In particular, this action deploys your website to a different repo, which will contain the previews of all the repos you choose to use this on. 

If you're interested in the logic behind this action, you can check out the [flow diagram](docs/flow_diagram.md).

## Setup

### Preview repo

#### Using my template

1. Go to [this template](https://github.com/EndBug/preview-template) and generate your repo from there: click "Use this template", fill in name and description, check that "Include all branches" is ticked, and create the repo.  
  It doesn't matter whether you create it as public or private, but remember that the Pages website will always be public.

2. Go into your repo settings, in the Pages tab (Repo settings > Pages) and set "GitHub Actions" as the source.

#### Manually

1. Create a new repo that will host your previews.  
  This repo will be used for the previews from all your repositories, so you'll need to set this up only once.

2. Make sure that this repo has two branches: `main` and `gh-pages` (you can also choose different names).
    - `main` should be your default branch, and it will only hold a workflow (and any additional files you want to add, liKE a README, a license, etc.). 
    - `gh-pages` will be the branch that will contain the actual previews, and it should be empty.

3. Create a new file in the `main` branch, and name it `.github/workflows/preview.yml`. Then copy the contents of [`dependents/preview-repo.yml`](dependents/preview_repo.yml) into it.  
  You shouldn't need to change anything in this file, the config options will all be in the source repo workflow.  
  This file might need to be updated if you update the action to a different major version.

4. Go into your repo settings, in the Pages tab (Repo settings > Pages) and set "GitHub Actions" as the source.

### Personal Access Token (PAT)

In order for the action to be able to trigger the deployment in the preview repo from the source repo, you'll need to create a Personal Access Token (PAT).  

There are currently two types of PATs: fine-grained, which are more secure but still in beta, and classic. I'd suggest to use fine-grained PATs, but if you can't, you can also use classic PATs.  

#### Fine-grained PAT

1. If you're using a GitHub organization, you may have to first enable _Personal Access Tokens_ (PAT) on the Organization's (not yours') Settings at `.../settings/personal-access-tokens-onboarding
1. Go to [Account settings > Developer settings > Fine-grained tokens](https://github.com/settings/tokens?type=beta). For an Org, you must use YOUR (not the Org's) Setttings, and change the _Resource owner_ from you to the Org on this screen.
2. Click on "Generate new token".
3. Give it a recognizable name and set an appropriate expiration date.
4. Make sure that the "Resource owner" is the same user/org that owns the preview repo.
5. Set the "Repository access" to "Only selected repositories" and then select the preview repo.
6. In the "Repository permissions" sections, set "Actions" and "Content" to "Read and write". "Metadata" will also be granted as "Read-only", as it is required for the other two.
7. Click on "Generate token", copy the token and save it somewhere for later.

#### Classic PAT

1. Go to [Account settings > Developer settings > Tokens (classic)](https://github.com/settings/tokens).
2. Click on "Generate new token" > "Generate new token (classic)"
3. Give it a recognizable name and set an appropriate expiration date.
4. Select the `repo` scope.
5. Click on "Generate token", copy the token and save it somewhere for later.

### Source repo

This steps need to be repeated for each repo you want to use this action on.

1. Go to the repo that contains the source code of your website.
2. Go to Repo settings > Secrets and variables > Actions.
3. Create a new repository secret called `PREVIEW_TOKEN` and paste the PAT you created in the previous step.
4. Add **two** workflows to the source repo, using the templates as a starting point:
   - [`dependents/source_repo_build.yml`](dependents/source_repo_build.yml) — checks out the PR/branch, builds the site, and uploads the result as an artifact. This workflow has **no secrets**.
   - [`dependents/source_repo_deploy.yml`](dependents/source_repo_deploy.yml) — downloads that artifact and runs this action with `PREVIEW_TOKEN`. It also removes previews when a PR is closed or a branch is deleted.

  The `name:` of the build workflow must match the `workflows:` list in the deploy workflow (`Build preview` in the templates).  
  Make sure to change the `PREVIEW_REPO` and `PAGES_BASE` env variables, along with the commands needed to build your website.  
  Also, make sure to change `EndBug/pages-preview`'s inputs to match your needs: more info on that in the ["Inputs"](#inputs) section of this file.

  Never checkout or build pull request code in a workflow that has `PREVIEW_TOKEN`. A fork PR can change install/build scripts and steal that secret. Use `pull_request` (no secrets) for the build, and only give secrets to a follow-up `workflow_run` job that consumes the artifact. Do not dispatch the deploy workflow from the build job: fork PRs have no token that can start a privileged workflow, and any secret you added there could be stolen.

  `workflow_run` does not carry pull_request/push context the action can infer from, so the build template uploads a small `preview-meta` sidecar (PR number or branch name) next to the site artifact. That metadata is a hint only — the PR author controls the build workflow — and must never include secrets. The deploy template verifies it against `workflow_run.head_sha` / `head_branch` before passing `action` and `pr_number` or `ref` to this action.

  You can pin the action to a commit SHA instead of `@v1` if you want to lock the exact revision.

All done! You're now ready to use the action 🎉

### Manual deploy or remove

The deploy template includes a `workflow_dispatch` job. You can also run the action from `workflow_dispatch` (or any other event) by passing the optional `action`, `pr_number`, `ref`, and `ref_type` inputs. Omitted values fall back to the GitHub event payload, so existing workflows behave the same.

Typical use case: remove a leftover PR preview after a failed cleanup run:

```yaml
on:
  workflow_dispatch:
    inputs:
      action:
        description: deploy or remove
        required: true
        type: choice
        options: [deploy, remove]
      pr_number:
        description: PR number (for PR previews)
        required: false
        type: string

- uses: EndBug/pages-preview@v1
  with:
    build_dir: build
    preview_base_url: ${{ env.PAGES_BASE }}
    preview_repo: ${{ env.PREVIEW_REPO }}
    preview_token: ${{ secrets.PREVIEW_TOKEN }}
    action: ${{ inputs.action }}
    pr_number: ${{ inputs.pr_number }}
```

## Inputs

```yaml
- uses: EndBug/pages-preview@v1
  with:
    # The directory in which the website has been built, in the a/b/c format
    build_dir: build

    # The GitHub Pages base URL of the preview repo
    preview_base_url: https://octocat.github.io/preview

    # The repository to push previews to, in the Owner/Name format
    preview_repo: octocat/preview

    # The token to access the preview repo, that you created during setup
    preview_token: ${{ secrets.PREVIEW_TOKEN }}

    # --- OPTIONAL ---
    # The name of the environment to use for the deployment
    # Default: 'preview'
    deployment_env: 'development'

    # Whether to use the deployments API
    # Default: 'true'
    deployments: false

    # The name of the author of the resulting commit
    # Default: the GitHub Actor
    git_author_name: Mona

    # The email of the author of the resulting commit
    # Default: the GitHub Actor's
    git_committer_name: mona@users.noreply.github.com

    # The committer of the resulting commit
    # Default: copies git_author_name
    git_committer_name: GitHub Actions

    # The email of the committer of the resulting commit
    # Default: copies git_author_email
    git_committer_email: 41898282+github-actions[bot]@users.noreply.github.com

    # Whether to comment on PRs
    # Default: 'true'
    pr_comment: 'false'

    # The name of the branch that hosts the previews
    # Default: gh-pages
    preview_branch: custom-pages-branch

    # The name of the workflow file that contains the comment workflow in the preview repo
    # Default: preview.yml
    preview_workflow_file_name: custom_workflow.yml

    # --- MANUAL OVERRIDES (optional) ---
    # Override deploy/remove; defaults from the event payload. Required on workflow_run
    # and on workflow_dispatch when pr_number or ref is set.
    action: remove

    # PR number for repo/pr/N previews; defaults from github.event.number
    pr_number: '12'

    # Branch name or git ref for repo/branch/name previews; defaults from the push/delete payload
    ref: my-feature-branch

    # branch or tag; defaults from the event payload. Tags are ignored (action none).
    ref_type: branch
```

## Contributors ✨

Thanks goes to these wonderful people ([emoji key](https://allcontributors.org/docs/en/emoji-key)):

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/EndBug"><img src="https://avatars.githubusercontent.com/u/26386270?v=4?s=100" width="100px;" alt="Federico Grandi"/><br /><sub><b>Federico Grandi</b></sub></a><br /><a href="https://github.com/EndBug/pages-preview/commits?author=EndBug" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="http://www.vorburger.ch"><img src="https://avatars.githubusercontent.com/u/298598?v=4?s=100" width="100px;" alt="Michael Vorburger"/><br /><sub><b>Michael Vorburger</b></sub></a><br /><a href="https://github.com/EndBug/pages-preview/commits?author=vorburger" title="Documentation">📖</a> <a href="https://github.com/EndBug/pages-preview/commits?author=vorburger" title="Code">💻</a></td>
    </tr>
  </tbody>
  <tfoot>
    <tr>
      <td align="center" size="13px" colspan="7">
        <img src="https://raw.githubusercontent.com/all-contributors/all-contributors-cli/1b8533af435da9854653492b1327a23a4dbd0a10/assets/logo-small.svg">
          <a href="https://all-contributors.js.org/docs/en/bot/usage">Add your contributions</a>
        </img>
      </td>
    </tr>
  </tfoot>
</table>

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->

This project follows the [all-contributors](https://github.com/all-contributors/all-contributors) specification. Contributions of any kind welcome!