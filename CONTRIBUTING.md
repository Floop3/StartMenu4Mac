# Contributing to StartMenu4Mac

Thank you for helping improve the project. Keep changes focused and explain the user-visible reason for a larger change before implementing it.

## Code contributions

- Avoid unrelated refactors, new dependencies, or new test frameworks.
- For a large change, share the goal in an issue or discussion before opening a pull request.
- Run this before submitting code or Xcode-setting changes:

  ```bash
  bash scripts/check.sh
  ```

  Add `--full` for the final Debug/Release, metadata, and packaged-resource checks. The public checks do not run Git synchronization or modify repository files.

- Do not claim real-device behavior from a build alone. Describe any manual checks that were or were not performed.

## Translation contributions

Add a language using Apple's standard layout:

```text
StartMenu4Mac/<locale>.lproj/Localizable.strings
```

The public check script discovers every locale containing `Localizable.strings`; no locale name needs to be added to the script.

When translating:

- Keep localization keys unchanged.
- Translate values only.
- Do not remove keys.
- Preserve format placeholders such as `%@`, `%d`, and other placeholder forms exactly.
- Run `bash scripts/check.sh` before submitting the translation.

The initial additional locales are Simplified Chinese (`zh-Hans`), Traditional Chinese (`zh-Hant`), Korean (`ko`), German (`de`), French (`fr`), and Spanish (`es`). Community human review of translations and terminology is welcome; machine-assisted drafts may be submitted for review.

Preserve every format placeholder exactly, including its spelling, type, and count. Examples include `%@`, `%d`, positional forms such as `%1$@`, and escaped percent signs (`%%`). Do not translate or reorder placeholders unless their positional form keeps the corresponding values correct.

The current workflow uses `.strings` files. Do not add a parallel String Catalog as part of a translation contribution.

## License and contributor agreement

The Software is governed by the custom
[StartMenu4Mac Source Available License](LICENSE). This is not an
OSI-approved open-source license. See the LICENSE for restrictions
on selling forks and for source-availability conditions.

**Upstream pull requests require explicit acceptance of
the [Contributor License Agreement](CLA.md) (CLA).** The CLA lets
Floop3 use accepted Contributions in future commercial, proprietary,
closed-source versions without additional permission or royalties.
Contributors keep their own copyright.

Before a PR is merged:
1. Read CLA.md and understand the future relicensing grant.
2. Check the PR template and post the exact affirmative CLA statement
   as a separate comment on the PR from the contributor account.
3. Identify third-party sources, assets, and AI-generated material whose
   rights or provenance are uncertain; obtain any employer consent needed.
4. A maintainer verifies the acceptance, identity, and any organizational
   authorization. Do not merge contributions lacking recorded consent.

**Forking, reading, using, or freely redistributing the project does
not require agreement to the CLA.** Those activities are governed by
LICENSE. A checklist without explicit recorded acceptance is not
treated as sufficient for upstream contribution.

The project is provided without guaranteed support, response times,
or acceptance of contributions.
