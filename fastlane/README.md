# Shipping Mozz

App Store Connect operations use an API key, so uploads need no Apple ID
password or 2FA prompt. Archive signing uses the paid team already signed into
Xcode on this machine. Provision App Store profiles for both Mozz and MozzWidget
in Xcode once; App Manager API keys cannot create provisioning profiles.

Secrets live in `.env.fastlane` at the repo root, which is gitignored along with
the `.p8` key it points at. Neither ever gets committed.

Start from `.env.fastlane.example`:

```sh
cp .env.fastlane.example .env.fastlane
$EDITOR .env.fastlane
```

Every lane takes `--env fastlane` to load it.

## One-time setup

```sh
fastlane bootstrap_testflight --env fastlane
```

This fills in the parts of App Store Connect a build alone doesn't:

- the beta description and feedback address testers see in TestFlight,
- the App Review contact details and demo account,
- an external tester group with a **public join link** enabled.

It's idempotent: running it again updates rather than duplicates.

### The demo account is not optional

Mozz has no catalogue of its own; it plays what's on a server you own. A
reviewer who can't sign in sees a login form and nothing else, which is a
rejection under guideline 2.1. So `MOZZ_DEMO_SERVER_URL`,
`MOZZ_DEMO_ACCOUNT_NAME` and `MOZZ_DEMO_ACCOUNT_PASSWORD` need to point at a
server reachable from outside your network that stays up for the length of the
review.

Whatever music is on it should be freely licensed: public domain or Creative
Commons, since Apple will stream it.

## Shipping a beta

The public beta starts at **0.1.0**. `MARKETING_VERSION` in `project.yml` is the
source of truth for every platform. TestFlight build numbers are separate and
increase for each upload.

Write what testers should look at, then ship:

```sh
echo "Playback after relaunch, lyrics, and CarPlay." > WHAT_TO_TEST.txt
fastlane beta --env fastlane
```

`beta` takes the next build number from TestFlight itself, not the commit
count, which can go backwards between branches. It rebuilds the audio engine
from the release source and stamps the app and widget
extension together, archives with signing explicitly enabled, exports for team
`N8Z5T4AK3X`, uploads, and submits to Apple's beta review for external
distribution.

Notes can also come from the environment:

```sh
MOZZ_WHATS_NEW="Playback after relaunch, lyrics, and CarPlay." fastlane beta --env fastlane
```

Once beta review clears:

```sh
fastlane testflight_link --env fastlane
```

prints the public URL anyone can use to join.

## Shipping to the App Store

```sh
fastlane release --env fastlane
```

This uploads the binary. Screenshots, description, and the actual "submit for
review" step stay in the App Store Connect web UI.

Bump `MARKETING_VERSION` in `project.yml` before a release and tag the exact
commit used for the upload.

## Other lanes

| Lane | What it does |
| --- | --- |
| `build` | Archives a signed `.ipa` into `build/`, uploads nothing |
| `generate_project` | Regenerates `Mozz.xcodeproj` |
| `testflight_link` | Prints the public beta link |

## Why a release Xcode gets forced

App Store Connect rejects anything built against a beta SDK (`altool` error
90534). Every lane that compiles calls `select_release_xcode`, which points
`DEVELOPER_DIR` at a release Xcode. If only a beta is installed the lane stops
rather than spending a build on an upload that would bounce.
