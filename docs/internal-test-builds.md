# Build an internal test package

1. Push the branch containing the change and this workflow.
2. Open Actions > **iOS IPA** > **Run workflow** and select that branch.
3. When the run succeeds, download the **Poki-internal** artifact. The run summary identifies the
   branch, commit, version, and build. The ZIP contains the IPA, signing files, and `SHA256SUMS`.
4. Keep the ZIP intact and give testers the [installation guide](install-internal-build.md).

This manual workflow builds the external edition and uploads an Actions artifact. It does not
create a tag or Release, change a channel, or promote a build. Reusable release callers keep their
explicit version, build, artifact name, and IPA filename.

## Build numbers

Manual runs use `9000 + GITHUB_RUN_NUMBER`, starting at 9001. A rerun keeps the same build number.
The workflow reads the branch version and the current official main version, then uses the greater
numeric version. It fetches official main without changing the checked-out source commit.

Public builds currently use main's commit count. Alpha, Beta, and Stable reuse those build numbers.
The workflow requires that count to be below 9000 and the run number to be at most 999. If either
range is exhausted, it stops before compilation instead of producing a lower or five-digit build.
Maintainers must choose a replacement policy at that point.

The four-digit integer fits both [Apple's documented build format](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html)
and Poki's integer build comparison. A `-test` suffix or dotted build would break that comparison.
The `Poki-internal` artifact and IPA filename identify the package as an internal build.
The guarantee uses the current public numbering policy and the official-main snapshot at build
start. It does not cover manually published packages with arbitrary version numbers. A later
public marketing version can supersede an installed internal build.

## Share without a GitHub login

[Actions artifact downloads require GitHub sign-in](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts).
The maintainer downloads the ZIP once. Testers can then receive it without a GitHub account.
Choose the delivery route before sharing any package.

| Proposed route | Tradeoff |
| --- | --- |
| Attach the ZIP in the existing test group | Recommended for a small group. No new public host. Group membership and file-size limits still apply. |
| Put the ZIP on an approved file host with an anonymous download link | Easier to share, but anyone with the link may download it. Requires owner approval for the host, access policy, and retention. |

No package is uploaded to a new host by this workflow. The owner still needs to select the test
group or approve a download location. Do not use a Release for internal distribution.
