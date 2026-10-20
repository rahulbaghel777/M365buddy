# Enable GitHub-powered comments on M365Buddy

M365Buddy uses [Giscus](https://giscus.app/) to embed comments backed by GitHub Discussions. The site code is in place, but the widget stays in fallback mode until the repository's Discussions category ID is configured.

## 1. Enable Discussions

1. Open [the M365Buddy repository](https://github.com/rahulbaghel777/M365buddy).
2. Open **Settings** and scroll to **Features**.
3. Select **Set up discussions** and finish the initial welcome-discussion setup.
4. Open **Discussions** and manage the categories. Create a category named **Comments** with the **Announcement** format. Keep the default **Q&A**, **Ideas**, **Show and Tell**, and **Announcements** categories enabled if you want the four community cards to work as written.

GitHub's current instructions are in [Enabling or disabling GitHub Discussions for a repository](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/enabling-or-disabling-github-discussions-for-a-repository).

## 2. Authorize Giscus for this repository

1. Open [the Giscus GitHub App](https://github.com/apps/giscus) and install/authorize it for **rahulbaghel777/M365buddy**.
2. Open [giscus.app](https://giscus.app/).
3. Enter `rahulbaghel777/M365buddy` as the repository and select the **Comments** category.
4. Copy the generated **Category ID**. It should start with `DIC_`.

## 3. Add the category ID to the site

Edit `public/assets/community-comments.js` and replace:

```js
categoryId: "GISCUS_CATEGORY_ID_PENDING",
```

with the exact `DIC_...` value produced by giscus.app. Do not invent or manually construct the ID. The repository ID is already populated in the file.

Commit/deploy the change. The community links will then activate and article pages will load the Giscus widget. The `pathname` mapping gives each page path its own discussion thread.

## 4. Verify

- Visit an article page and confirm the comment widget appears below the article content.
- Sign in with a GitHub account and test posting a comment.
- Open `/community/` and test the discussion/category links.
- If the widget cannot load, the page keeps a fallback with a GitHub Issues link instead of leaving a blank comment area.

Comments are public. Never include passwords, app secrets, certificates, access tokens, real tenant identifiers, internal URLs, or unredacted logs in a discussion.
