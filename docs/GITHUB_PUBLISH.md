# 把 FocusCull 发布到 GitHub

这份指南按「第一次发布」来写。照着做即可，不需要先学 Git。

> 当前 FocusCull 工作区已经初始化 Git 并完成首个 commit；如果你就在当前机器上继续，**跳过第 4 步**，直接从第 5 步开始。第 4 步只适用于一个还没有 `.git` 的全新目录。

---

## 0. 先理解三件事

- **Git**：本机的版本管理工具，负责记录提交（commit）。
- **GitHub**：远程仓库，负责托管代码、截图和 Release 下载包。
- **Release**：GitHub 仓库的「正式发布」页面，可以挂 ZIP、写更新说明。别人下载的是 Release 里的 ZIP，不是仓库源码。

发布完成后，你的仓库大概长这样：

```text
FocusCull/
├── Sources/                 源码
├── Resources/               图标
├── scripts/build_app.sh     构建脚本
├── docs/screenshots/        截图
├── docs/GITHUB_RELEASE_NOTES.md
├── dist/FocusCull-1.4.1-macOS.zip
├── README.md
├── 使用说明.md
├── CHANGELOG.md
├── LICENSE
└── .gitignore
```

`dev/`、`.build*/`、`.cache/`、`dist/release/` 已在 `.gitignore` 中排除，不会误传。

---

## 1. 创建 GitHub 账号（已有可跳过）

1. 打开 <https://github.com>，点 **Sign up**。
2. 验证邮箱。
3. 建议开启两步验证：**Settings → Password and authentication → Two-factor authentication**。

---

## 2. 在 GitHub 网页创建仓库

1. 右上角 **+** → **New repository**。
2. 填写：
   - **Repository name**：`FocusCull`
   - **Description**：
     ```text
     为生态、航空、体育、汽车/摩托车追焦摄影师打造的 macOS 连拍合焦初筛器：用 M 芯片的 Metal GPU + Neural Engine 本地分析，快速找出合焦瞬间。
     ```
   - **Public**（想公开）或 **Private**（只自己看）。
3. **不要**勾选：
   - Add a README file
   - Add .gitignore
   - Choose a license

   因为本地已经有这些文件，勾选会造成第一次推送冲突。
4. 点 **Create repository**。

创建后页面会显示仓库地址，例如：

```text
https://github.com/你的用户名/FocusCull.git
```

---

## 3. 配置 Git（只需一次）

打开「终端」，执行：

```bash
git --version
```

如果没有 Git：

```bash
xcode-select --install
```

设置提交身份（把邮箱换成你的 GitHub 邮箱）：

```bash
git config --global user.name "Lee"
git config --global user.email "你的GitHub邮箱"
```

检查：

```bash
git config --global --list
```

---

## 4. 在本地初始化并提交

```bash
cd /path/to/FocusCull

git init
git branch -M main
git add .
git status
```

**重点检查 `git status`：**

- 应该看到 `README.md`、`Sources/`、`docs/`、`dist/FocusCull-1.4.1-macOS.zip` 等。
- **不应该**看到 `.build-app/`、`.cache/`、`dev/`、`dist/release/`、`dist/FocusCull.app/`。
- `.DS_Store` 也不应该出现。

确认无误后提交：

```bash
git commit -m "FocusCull 1.4.1: Metal + Neural Engine photo culling"
```

---

## 5. 推送到 GitHub

### 方案 A：GitHub Desktop（最适合第一次）

1. 安装 [GitHub Desktop](https://desktop.github.com/)。
2. 登录 GitHub 账号。
3. **File → Add local repository**，选择：
   ```text
   /path/to/FocusCull
   ```
4. 点 **Publish repository**。
5. 取消勾选 **Keep this code private**（如果要公开）。
6. 发布。

### 方案 B：官方 CLI `gh`（推荐，命令少）

```bash
brew install gh
gh auth login
```

按提示选择 **GitHub.com → HTTPS → Login with a web browser**。

然后：

```bash
cd /path/to/FocusCull

gh repo create FocusCull --public --source=. --remote=origin --push
```

如果仓库已经在网页创建过，用：

```bash
git remote add origin https://github.com/你的用户名/FocusCull.git
git push -u origin main
```

### 方案 C：HTTPS + Token

GitHub 早已不支持用账号密码推送。需要 Personal Access Token：

1. GitHub → **Settings → Developer settings → Personal access tokens → Tokens (classic)**。
2. **Generate new token (classic)**。
3. 勾选 **repo**。
4. 生成后复制 token（只显示一次）。

然后：

```bash
git remote add origin https://github.com/你的用户名/FocusCull.git
git push -u origin main
```

提示密码时，**粘贴 token**，不是 GitHub 登录密码。

> 不要把 token 写进 README、脚本或提交记录。

---

## 6. 创建 Release（别人下载的正式版本）

### 网页方式

1. 打开仓库 → 右侧 **Releases** → **Draft a new release**。
2. **Choose a tag**：输入 `v1.4.1` → **Create new tag on publish**。
3. **Target**：`main`。
4. **Release title**：
   ```text
   FocusCull 1.4.1 — HIF 10-bit 支持 + 实拍回归
   ```
5. **Describe this release**：把 `docs/GITHUB_RELEASE_NOTES.md` 的内容整段粘贴进去。
6. **Attach binaries**：上传：
   ```text
   dist/FocusCull-1.4.1-macOS.zip
   ```
7. 点 **Publish release**。

### 命令行方式

```bash
cd /path/to/FocusCull

gh release create v1.4.1 dist/FocusCull-1.4.1-macOS.zip \
  --title "FocusCull 1.4.1 — HIF 10-bit 支持 + 实拍回归" \
  --notes-file docs/GITHUB_RELEASE_NOTES.md
```

发布后，Release 页面会有一个可直接下载的 ZIP。

---

## 7. 把仓库首页整理好

在仓库首页点右侧 **About** 的齿轮：

**Description：**

```text
为生态、航空、体育、汽车/摩托车追焦摄影师打造的 macOS 连拍合焦初筛器：用 M 芯片的 Metal GPU + Neural Engine 本地分析，快速找出合焦瞬间。
```

**Topics：**

```text
macos swift swiftui metal neural-engine apple-silicon vision
photo-culling focus-detection photography burst-photos privacy
```

**Social preview：**

上传 `docs/screenshots/browser-dark.png`（仓库 → Settings → Social preview）。

---

## 8. README 里的下载链接

当前 README 的下载按钮指向：

```text
dist/FocusCull-1.4.1-macOS.zip
```

因为 ZIP 已经提交到仓库，这个链接在 GitHub 上可直接下载。

发布 Release 后，也可以再加一条「最新版」链接，把 `你的用户名` 换成实际用户名：

```markdown
[下载最新版](https://github.com/你的用户名/FocusCull/releases/latest)
```

两种方式可以同时保留。

---

## 9. 发布后检查清单

- [ ] 仓库首页能看到 README、截图、AI 主体筛选和 Metal/Neural Engine 介绍。
- [ ] `git status` 干净，没有 `.build`、`dev`、`.DS_Store`。
- [ ] Release `v1.4.1` 已发布，ZIP 可下载。
- [ ] 下载 ZIP，解压后 `FocusCull.app` 能打开。
- [ ] 仓库 About 的 Description、Topics、Social preview 已设置。
- [ ] README 没有 `你的用户名` 之类的占位符（如果加了 Release 链接）。
- [ ] LICENSE 与截图版权说明已保留。

---

## 10. 常见问题

### `git: command not found`

```bash
xcode-select --install
```

### `Authentication failed` / `Support for password authentication was removed`

不要用 GitHub 登录密码。使用：

```bash
gh auth login
```

或 Personal Access Token（勾选 `repo`）。

### `remote origin already exists`

```bash
git remote set-url origin https://github.com/你的用户名/FocusCull.git
```

### `src refspec main does not match any`

还没有提交：

```bash
git add .
git commit -m "FocusCull 1.4.1"
git push -u origin main
```

### 不小心把 `.build` 或 `dev` 加进了暂存区

```bash
git rm -r --cached .build-app .build-tool .cache dev 2>/dev/null
git status
```

`.gitignore` 已经覆盖这些目录；正常 `git add .` 不会加入。

### GitHub 提示文件太大

当前 ZIP 约 3.2 MB，远低于 GitHub 100 MB 限制。不要提交 `.build` 或 `.app` 目录。

### 别人下载后 macOS 提示「无法验证开发者」

这是 ad-hoc 签名、未公证导致的。让用户：

- 右键 `FocusCull.app` →「打开」；或
- 系统设置 → 隐私与安全性 →「仍要打开」。

---

## 11. 可选：后续增强

- 给仓库加 **GitHub Actions**，在打 tag 时自动构建 ZIP。
- 做 **Apple Developer ID 签名 + 公证**，用户双击即可打开。
- 发布 **Homebrew Cask**：
  ```bash
  brew install --cask focuscull
  ```
- 添加 Issue 模板、Discussions、贡献指南。
- 在 README 顶部加 Release 徽章和下载量徽章。

第一次发布，先把「源码 + README + Release ZIP」跑通，就已经是一个完整、可分享的开源项目了。
