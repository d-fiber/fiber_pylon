# pylon example

Three backends behind one contract, and a console script that cannot tell them apart.

```
flutter run -t lib/main.dart
```

Plain `dart run` cannot start this: pylon's storage toolkit (`LocalStorage`, `ValkeryStorage`)
depends on `sqflite` and `shared_preferences`, real Flutter plugins that pull in `dart:ui`,
which the bare Dart VM does not have. A connected device or simulator is enough; nothing here
opens a window.

It runs the same sequence — describe the backend, read its credential state if it has one,
list its posts, read one back by id, wait for a live one if it can push — against each of the
three backends in turn, and prints what came back. The sequence never changes; only the
backend behind `PostsSdk.I` does.

## What each one is

**memory** holds three posts in a list. No network at all. It exists to prove the barrier:
if the screen works against this, the screen depends on the contract and on nothing else,
and no amount of reading the code demonstrates that as well as running it. It is also what
the tests in `test/` run against.

**jsonplaceholder** talks to `jsonplaceholder.typicode.com`. Posts arrive with numeric ids
and a numeric author. No credential.

**dummyjson** talks to `dummyjson.com`. Different failure vocabulary, a list wrapped in a
`posts` envelope, tags where the other server has an author, and a token that expires in a
minute so the renewal happens while you are watching. The strip under the buttons shows
whether the credential is held and whether it has entered the renewal window.

## Where to look

```
lib/contract/     the barrier: Post, PostPort, the two error enums, ExampleBackend
lib/backends/     three adapters, each with its own signals and its own tables
lib/main.dart     the map of backends and the sequence run against each, in turn
```

Read `lib/backends/placeholder/` and `lib/backends/dummyjson/` next to each other. They face
two servers that disagree about almost everything, and they hand the same `Post` upwards.

Three things are worth noticing in them.

**The signal enums are different.** `PlaceholderSignal` and `DummySignal` name different
failures, because the two servers fail differently. Neither is pylon's, and pylon reads
neither.

**The classifiers are the only files that read a status code.** `DummyClassifier` also reads
the body, because that server distinguishes two 404s in a `message` field. The contract
above never learns that this refinement exists.

**The tables live beside the adapters.** `_readPost` and `_listPosts` are declared in each
backend file, because they translate one server's vocabulary. Swapping servers means writing
new ones; `ReadPostError` and `ListPostsError` do not move.

## The credential

`DummyBackend` signs in during `initialize()` with the account DummyJSON publishes for its
sandbox, and asks for a token that lasts one minute against a renewal window of twenty
seconds. So forty seconds after the app starts, the renewal fires on its own and the strip
changes.

The backend writes one method for that, `DummyRefresher.refresh`. Renewing ahead of expiry,
collapsing simultaneous attempts into one exchange, retrying a failure that may pass and
revoking one that will not are all `CredentialManager`, and the other two backends get them
for free by not needing them at all.

## The tests

```
flutter test
```

They run against `MemoryBackend`, with no network and no waiting, which is what the memory
backend is for.

## The local database

`lib/src/database/` shows a project's own typed database: `User` is a `Model` with its
`Field`s declared next to the fields they name, and `OwnDatabase` declares the `users`
collection. `GroundSdk` initializes it in its own `initialize()` and closes it in `dispose()`,
so it needs `configureSdk()` to have run first, like everything that lives in the app's own
database file.

```dart
final db = GroundSdk.I.database;
await db.users.doc('ada').set(const User(name: 'Ada', age: 36));
final adults = await db.users
    .where((w) => w(User.age_).isGreaterThanOrEqualTo(18))
    .orderBy((o) => [o.asc(User.name_)])
    .get();
```

Its `users` collection is isolated, so on sign-in `Tenant.use(account.id)` gives each account
its own users, and `Tenant.leave()` on sign-out goes back to the anonymous ones. A collection
declared with `tunnel: Tunnel.shared` would be one copy for everybody.
