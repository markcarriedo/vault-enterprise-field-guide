
## 2026-09-11
### 🚀 Features
- *(vault)* Dynamic AWS credentials via the AWS secrets engine ([6de9235](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/6de9235e637ef7c0d90c22b8f0d95987dad094e3))

## 2026-09-10
### 🚀 Features
- *(vault)* AWS auth method instead of AppRole, off the root token ([818c90a](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/818c90a627154a9095aa6cf1c39e38b25ac6ee5e))
- *(changelog)* Nest by day then commit type ([719c0a5](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/719c0a55a08da05831738cd9ab8bcbfdf5c56be1))
- *(changelog)* Group entries by commit type instead of by day ([3b4b446](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/3b4b44609a874d3e914c59f338924684d2ff7a7c))
- *(vault)* Manage the secret/ mount and field-guide-app policy in Terraform ([6d26e3a](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/6d26e3a2e530be06c96c8a112b120435e5d05308))
- *(vault)* Enable KV v2, write a verified least-privilege policy ([4d62fba](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/4d62fba8c56d906a3ccb9624dc8b6e981909df63))
- *(vault)* Initialize and unseal the cluster - it's live ([080c623](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/080c623e1c00c1f0b28112870e36cbbc2724ff12))
- *(changelog)* Link the hash to its GitHub commit instead of code-formatting it ([bbc3736](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/bbc373617e6e859b3edfdf729c735318f9d3d014))
- *(changelog)* Show short commit hash, via pre-commit stage not post ([981fedc](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/981fedc74495c5f156f15cd77cab35b9ea66f7f5))
- Restore the journal, make CHANGELOG.md purely mechanical ([020dc5f](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/020dc5f3433df905011d4edc27d9c399cc18b4a3))
- *(terraform)* Scaffold the HVD module invocation ([0318080](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/03180803db866d648a19b64a45654385e8bfde44))
- *(terraform)* TLS via private Route53 zone + self-signed CA ([80d9c0b](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/80d9c0b11f1936731506ad41ab91bed439754af8))

### 🐛 Bug Fixes
- *(changelog)* Revert commit-hash addition, self-amend can't converge ([1760a7b](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/1760a7bdb7fb8f63d503cf17f4b2bb251e119e43))
- *(mkdocs)* Stop Journal nav item rendering twice ([3dc6603](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/3dc660339f19a767e7b61523ebc2d49992f5f155))
- *(terraform)* Pin vault_version to 2.1.0+ent ([48a4206](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/48a4206b701fdcb0567bcf83b0bf830568c87c1e))

### 📚 Documentation
- Stop naming the internal credential broker by name ([9f6972f](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/9f6972fbb25dcc71972176ccfd3fd4f996e69fee))
- Stop naming the personal domain we considered and dropped ([0fb66c2](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/0fb66c24885c1f2add13345b853257324e0ca0bc))
- *(readme)* Shorten title, fix stale hook/changelog description ([772d299](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/772d29983ae6725b536f1828177168d7aa1bf6b9))
- Tone pass for expert narration, fix stale architecture status ([c79d5b1](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/c79d5b1a0e42bd945ae9d500850f8fa80d9fe621))
- *(journal)* Simplify to "a government agency", drop "tax" ([a7e06a9](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/a7e06a9f7c4667a39af909df563ad1bcc760a707))
- *(journal)* Remove named org from example, fix self-deprecating tone ([0537a7c](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/0537a7c3ac4c02ff7650abd19e2d455be738c98b))
- *(guide)* Remove stale stub chapters, renumber, update glossary ([e9f657e](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/e9f657e474baa16318a2b94ef419eb023b22fd0d))
- *(guide)* Document the manual cluster-connect runbook ([a32afdd](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/a32afddbd47fa0aed63381e384b6fd28c45cae3c))
- Fill in Installation guide page and real Architecture diagram ([cd9feee](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/cd9feee18bc95f64e31249a1cbfe4a36a5942e3a))
- *(decisions)* Record the changelog-hash / pre-commit-stage switch ([6920772](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/6920772178518d966f0463c0b79ff60543e02394))
- *(planning)* Validate cluster health; feat(mkdocs): polish homepage ([5ebf0f6](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/5ebf0f67ce1deabedf4db48920731894d6114c53))
- *(guide)* Fill in AWS Infrastructure page ([664846a](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/664846a7859a9352251fda6dad3eee7064b37445))

### 🚜 Refactor
- *(vault)* Drive mounts and policies from vault-config.yaml ([e72f62b](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/e72f62b324f8c716ab407dc79721235c74ad5a97))

### ⚙️ Miscellaneous Tasks
- *(changelog)* Regenerate to drop a stale entry from the history rewrite ([48aa096](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/48aa096a8f46228e3c1607849e8f40550a2928a1))

## 2026-09-09
### 🚀 Features
- *(changelog)* Auto-regenerate via a post-commit hook ([81807e7](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/81807e71a2349ae83a5292b988338a1746265d95))
- *(terraform)* Apply the state-bucket bootstrap, wire up S3 backend ([e5fa4fa](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/e5fa4faf166421b1dc73d0a021f1021ba4671b9d))
- *(terraform)* Scaffold state-bucket bootstrap and prerequisites config ([01096bf](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/01096bf11692a0822cb54232c2b41e29ea70784e))
- *(changelog)* Group entries by day instead of [Unreleased] ([677960c](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/677960c30344dbe8d7075e31d054a4f0c0b689c7))

### 🐛 Bug Fixes
- *(mkdocs)* Enable pymdownx.tilde so ~~strikethrough~~ actually renders ([f0ca5ff](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/f0ca5ff120f1a8bdfc9cf5a903c164da203415a0))
- *(mkdocs)* Render task-list checkboxes instead of literal [ ] ([0b3c880](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/0b3c8809bdc8bcb5aab6a0aea7f58121e7878864))
- *(ci)* Stop passing --config twice to git-cliff-action ([bf3b856](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/bf3b8560c851a9f6a5208160b247191f153862aa))

### 📚 Documentation
- *(planning)* Mark VPC/KMS/license prerequisites done ([a11c11c](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/a11c11c45ebb2bfb7fe7fb8c62c54c62f9141ab1))
- *(planning)* Record the full deployment sequence, local-only Terraform ([ce4c165](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/ce4c1653d6bb800208cf97f1250f97f189310b48))
- Move CHANGELOG.md to the repo root, out of the MkDocs site ([40447ae](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/40447ae185609d01abf783c82784f334dc103c83))
- Replace journal with a git-cliff generated changelog ([0b73b37](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/0b73b37a4aee4d96fb8fe308a175f685280ec5f1))
- *(journal)* Revive the journal, backfilled with the day's work ([45898d5](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/45898d55b4e10e3e9df82f6087ad8bd5b01a2d9d))
- *(planning)* Record target environment and AWS survey findings ([c2eff4f](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/c2eff4f26817f806219e58bc38274ec1d0d80a56))
- *(planning)* Document prerequisites for the HVD Vault Enterprise module ([ef02810](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/ef02810a38a61ce6957cf7fc9c42d35c072a3850))
- *(journal)* Drop the journal, guide + reference are the published output ([b1ab4b7](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/b1ab4b782b826aa87eb3beb4a236d5028da5f00d))
- *(readme)* Lead with the Vault content, not MkDocs mechanics ([e1bdd8a](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/e1bdd8ab23ea581f16263e83cc528ba5a82b1a22))

### 🎨 Styling
- *(nav)* Drop the right-align CSS, keep Journal in normal tab flow ([c118a9c](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/c118a9c1d6abf233b767f9d9307e3a4a0f127d4c))
- *(nav)* Reorder to Home/Guide/Reference/Journal, right-align Journal ([9d219bd](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/9d219bdf51fbb4385a96b0711858e9c51581d636))
- *(theme)* Use Vault's official brand colors and logo ([c7544f2](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/c7544f2a0ad6179a0ef56de9bba86a3399ca8c16))

### ⚙️ Miscellaneous Tasks
- Regenerate CHANGELOG.md, 6 commits behind ([8d1c27d](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/8d1c27dddb9a481001a7eff242a69631197276cd))
- *(pages)* Deploy docs to GitHub Pages via Actions ([f2cf234](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/f2cf23481a68726750cec70fa28d6a2337f38af4))
- *(security)* Add gitleaks pre-commit hook ([137242b](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/137242b778e733893a1891b75cb1bc4da3628caf))
- *(mkdocs)* Scaffold field guide site with Material theme ([af68c1d](https://github.com/markcarriedo/vault-enterprise-field-guide/commit/af68c1d539127d34f92de0edcc642393ce4e2ee2))
