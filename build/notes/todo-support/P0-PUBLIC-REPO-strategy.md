Here's a clean, self-contained writeup you can drop into a TODO or design doc.

---

# Contextify: Public Releases + Issues with Private Code

## 1. Overview

Goal:
Expose **public Releases and Issues for Contextify** while keeping the **actual source code private**.

We currently have:

* **Private code repo:** `banagale/contextify` (real code, internal work)

We want:

* A **public-facing GitHub presence** for Contextify:

  * Downloadable builds (DMG/ZIP) under **Releases**
  * Public **Issues** for users
  * A canonical public GitHub URL to link from the app/site

Key constraint: GitHub does **not** support "private code, public issues/releases" on a *single* repository. Repo visibility is all-or-nothing.

Solution: Use **two repositories**:

* Keep `banagale/contextify` private for development.
* Create **`peterpym/contextify`** as the public "product" repo for users.

---

## 2. Problem in Detail

### 2.1 GitHub visibility limitation

On GitHub, repository visibility is a single switch:

* **Public repo**

  * Code visible
  * Issues visible
  * Releases visible
  * Wiki/Discussions/etc. visible

* **Private repo**

  * Code **not** visible to non-collaborators
  * Issues, Releases, etc. are also **not** visible to non-collaborators

There is **no built-in way** to:

* Keep a repo's code private
* While making just **Issues** and/or **Releases** public

So the current private repository (`banagale/contextify`) cannot expose a public issues tracker or release page by itself.

### 2.2 Requirements

We need to satisfy:

* **Code privacy**

  * Full source code, internal docs, and implementation details must remain private.

* **Public presence for users**

  * Public **Releases**: DMGs/ZIPs/changelogs downloadable from GitHub.
  * Public **Issues**: users can file bugs and feature requests.
  * Stable, user-facing GitHub URL to link from:

    * The app (e.g., "Report a bug")
    * Website / documentation
    * Release notes / marketing materials

* **Clean naming**

  * Ideally, the public URL should look "nice" and product-focused.
  * Using the `peterpym/` org helps separate "publisher" identity from the `banagale/` personal dev workspace.

---

## 3. Proposed Architecture

### 3.1 Repositories

**Private development repo (existing)**

* `banagale/contextify` (private)

  * Full source code
  * Internal issues / TODOs / tech docs
  * CI workflows for building, testing, signing, etc.
  * Anything not meant for end users

**Public distribution + support repo (new)**

* `peterpym/contextify` (public)

  * **Issues** enabled - primary user bug/feature tracker
  * **Releases** enabled - host signed build artifacts (DMG/ZIP) and changelogs
  * **README**:

    * High-level product description
    * Installation instructions
    * Links to website/docs if any
    * Clarify that source code lives in a private repository and that this repo is for releases + issue tracking
  * Optionally:

    * Discussions (for broader community feedback)
    * Screenshots, marketing assets

### 3.2 Intentional separation of concerns

* **`banagale/contextify`**: Engineering workspace

  * You can treat this as the "real project."
  * Internal issues can be more technical and messy (stack traces, internal experiments, etc.).
  * Branches and tags for internal workflows, CI, and deployment.

* **`peterpym/contextify`**: User-facing surface

  * Clean, user-oriented Issues (bug templates, feature request templates).
  * Releases that map to user-visible versions (e.g., `v1.0.0`, `v1.0.1`).
  * Minimal or no code (could contain only marketing/README/docs).

This keeps user-facing communication clean, while giving you full freedom to move fast inside the private repo.

---

## 4. Release & Issue Flow

### 4.1 Development lifecycle (private)

1. All coding happens in `banagale/contextify`.
2. Internal Issues/PRs track work as usual.
3. CI runs (tests, linters, code signing validation, etc.) in the private repo.

### 4.2 Versioning

When you're ready to cut a user-facing release:

1. Decide on a **semantic version** (e.g., `v0.3.0`).
2. In `banagale/contextify`, tag the commit that corresponds to that release:

   * Example: `git tag v0.3.0` and push the tag (kept private).

This tag is your internal anchor for what went into the release.

### 4.3 Build & publish workflow (high-level)

From `banagale/contextify`:

1. Build the signed app bundle / DMG / ZIP.
2. Publish the release **to the *public* repo** `peterpym/contextify`.

At a high level, this can be:

* **Manual** (initially)

  * Build locally.
  * Manually create a Release in `peterpym/contextify` via the GitHub UI.
  * Upload the DMG/ZIP.
  * Paste in the changelog.

* **Automated via CI** (target state)

  * A GitHub Actions workflow in `banagale/contextify`:

    * Triggers on pushing a tag like `v*`.
    * Builds and signs the app.
    * Uses a GitHub Personal Access Token (or GitHub App) with permission on `peterpym/contextify`.
    * Calls the GitHub API (or uses an action) to:

      * Create or update a Release in `peterpym/contextify` with the same tag name / version number.
      * Upload the DMG/ZIP as release assets.
      * Optionally include the generated or curated changelog text.

The important point: **the publishing step happens from private → public**, but only artifacts and metadata are copied over, not the source code.

### 4.4 User-facing issues & links

In the app and any documentation, point users to the **public** repo:

* "Report a bug" / "Give feedback":

  * Link to `https://github.com/peterpym/contextify/issues/new/...`
* "Check for updates" / "Download latest version":

  * Link to `https://github.com/peterpym/contextify/releases`
* The app's About box / website "View on GitHub":

  * Link to `https://github.com/peterpym/contextify`

Users never see `banagale/contextify`; that's your internal working repo.

---

## 5. Implementation Checklist

This is the concrete step list you can make into TODOs.

### 5.1 Public repo setup

* [ ] Create new repo: `peterpym/contextify` (public).
* [ ] Enable:

  * [ ] Issues
  * [ ] Releases
  * [ ] (Optional) Discussions
* [ ] Disable any surfaces you don't want (e.g., Wiki, Projects).
* [ ] Add initial `README.md`:

  * [ ] Short product description
  * [ ] Supported macOS version(s)
  * [ ] Download instructions (point at Releases)
  * [ ] Note that the code lives in a private repository; this repo is for releases + issue tracking.
* [ ] Add license information (if desired) for the distributed binaries.

### 5.2 Wiring the app / docs to the public repo

* [ ] Update in-app "Report a bug" link → `https://github.com/peterpym/contextify/issues/new/...`
* [ ] Update any existing docs/website to reference `peterpym/contextify` as the canonical GitHub home.
* [ ] For any future auto-updater integration (e.g., Sparkle), plan to have the public appcast/releases served from URLs tied to `peterpym/contextify` or its assets.

### 5.3 Release process (initial manual version)

* [ ] Define a simple versioning scheme (e.g., semantic versioning with `vX.Y.Z` tags).
* [ ] For the next release:

  * [ ] Tag the release commit in `banagale/contextify`.
  * [ ] Build and sign DMG/ZIP in the private repo.
  * [ ] Go to `peterpym/contextify` → Releases → "Draft a new release":

    * [ ] Use the same tag name and version string.
    * [ ] Upload the DMG/ZIP.
    * [ ] Add changelog notes.
  * [ ] Publish the release.

### 5.4 Release process (future CI automation)

* [ ] Create a GitHub Personal Access Token or GitHub App with:

  * [ ] Permission to create releases and upload assets to `peterpym/contextify`.
* [ ] Add this credential as a secret in `banagale/contextify`.
* [ ] Create a GitHub Actions workflow in `banagale/contextify` that:

  * [ ] Triggers on tag pushes (e.g., `v*`).
  * [ ] Builds and signs the app.
  * [ ] Uses the token to:

    * [ ] Create/update a corresponding Release in `peterpym/contextify`.
    * [ ] Upload artifacts.
    * [ ] Attach changelog text (auto-generated or from a file).

---

## 6. Summary

* You **cannot** make Issues/Releases public while keeping code private in a single GitHub repo.
* The solution is to split responsibilities:

  * **`banagale/contextify`** - private dev repo with real code and internal workflows.
  * **`peterpym/contextify`** - public repo for Releases, Issues, and user-facing documentation.
* Releases flow one-way: **private → public**, moving only built artifacts + metadata, not source.
* All user-facing links (bug reports, downloads, "View on GitHub") should point to `peterpym/contextify`.

This gives you a clean, public GitHub presence for Contextify without exposing your private code.
