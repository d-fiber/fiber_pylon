# Contributing to pylon

## The licence, in one paragraph

Pylon is under the Mozilla Public License 2.0. You may use it for anything, including
commercially, change it, and combine it with files under any other licence, proprietary
ones included, licensing that larger work on your own terms. What you owe in return is
per file: keep the header on every file you received it on, and if you distribute a file
covered by it, publish that file's source under these same terms, including the changes you
made. The name "Fiber" and its branding are not part of the grant. `LICENSE` governs where
this paragraph and it disagree.

## Getting set up

```
git clone <this repository>
cd pylon
bash tool/test.sh
```

That resolves, analyses, checks the formatting and runs the suite. If it is green you have
everything you need; there is nothing else to install.

The suite runs on `flutter_test` rather than `package:test`, which is a constraint and not
a preference: `package:test` pins `analyzer` in a way that collides with the workspace
pylon is developed in. Nothing in `lib/` depends on Flutter.

## Where your work goes

```
lib/fiber_pylon.dart          the barrel, and the only thing a consumer imports
lib/fiber_pylon_io.dart       the one piece that needs dart:io, kept apart on purpose
lib/src/barrier/               what a port touches: Result, Fault, FaultMapper, Sdk,
                                Singleton, Config, RestNode, RestEndpoint, CallKey,
                                RealtimeNode, RealtimeTopic
lib/src/toolkit/               what only an Sdk implementation touches: CallGuard,
                                HealthMonitor, Observable, Reporter, RestClient and
                                what it needs, ChannelKeeper, SocketChannel, Backoff,
                                CredentialManager and what it needs, KeyValueStore,
                                Preference
test/                          one file per subject, named after it
```

A new public member is exported from `lib/fiber_pylon.dart` or it does not exist. A new file
carries the licence header, copied from the file next to it.

## The rule that governs every change

**Pylon understands neither side.** Before adding anything, ask what it assumes about the
project using it. If the answer names a token format, a status code's meaning, an error
name, a body shape or a frame layout, it belongs to an adapter and not here.

Two questions catch most of it:

- Would this still be right for a project that has no authentication? No list of error
  kinds survives that question, which is why there is none.
- Does this recognise a name the project chose? A table keyed on member names looks helpful
  until a project spells one differently, and then it wires the wrong thing silently.

Where pylon has to act on something only the project knows, it takes it as a required
argument. `fatalSignals`, `renewOn`, `duplicateSignal`, `expiresAt` and `fallback` all have
no default for this reason, and adding one would be a regression.

## Before you push

### Run what you wrote

Reading your own diff proves nothing: you read the intention, not the code. Call the thing
from a test, with real input, and with the input that should make it refuse. A refusal that
does not refuse is a whole bug.

### Write the test that would have caught it

A defect you fixed gets a test, and that test is written first and seen red before the fix
goes in. A fix applied to a bug that was never reproduced fixes a hypothesis.

`TESTING.md` says the rest.

### Say what you did not run

A verification you claim but did not perform is worse than none, because it hands over
confidence with nothing behind it. When something could not be exercised, say so and say
why.

## Commit messages

```
[TAG]: message
```

In English, imperative, no trailing period, under 72 characters. One subject per commit.

| Tag | For |
| --- | --- |
| `DEV` | new feature, new code |
| `BUGFIX` | a fix for something that was broken |
| `REFACTO` | moving or rewriting without changing behaviour |
| `DOC` | documentation only |
| `TEST` | tests only |
| `CI` | workflows and build tooling |
| `PERF` | speed or footprint |
| `SECURITY` | hardening, closing a leak |
| `BREAKING` | breaks a published API |
| `REVERT` | undoing an earlier commit |
| `CHORE` | dependencies and other housekeeping |

`.github/commits/check.sh` runs this in CI and locally. A message it rejects costs a
rebase; discovering it in CI costs a round trip.

## Versions, tags and main

Work lands on `dev`. Nothing is pushed to `main` by hand.

The version lives in `pubspec.yaml` and nowhere else. When you move it, the CI writes that
version's section of `CHANGELOG.md` from the commits since the last tag, commits it, and
tags the commit `v<version>`. When you do not move it, nothing is tagged and nothing is
written.

`main` is created automatically by the first green push to `dev`, and only that once. Every
promotion after it is manual: the repository owner runs the `promote` workflow with the
version, which checks that `dev` holds it and that the CI tagged it, merges `dev` into
`main`, and writes the release from the changelog.

A version that was never tagged has never been green, and the promotion refuses it.

## Where the work stops

Some things are deliberately not here, and a pull request adding them will be turned down
with this paragraph rather than a discussion:

- a list of error kinds, statuses or codes pylon interprets;
- a default for an argument only the project can answer;
- anything that reads a member name to decide behaviour;
- an envelope, a token format or a frame layout;
- a code generator.

If one of those would genuinely help you, the shape to propose is the seam that lets you
supply it, as `RestClassifier` and `SocketProtocol` already do.
