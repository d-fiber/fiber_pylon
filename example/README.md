# pylon example

Three backends behind one contract, and a screen that cannot tell them apart.

```
flutter run
```

Pick a backend from the row of buttons at the top. The list below is the same widget every
time, holding the same `PostPort`, and it has no way to find out which one answered.

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
lib/ui/           one screen, which imports the contract and never an adapter
lib/main.dart     the map of backends, which is the whole of the swap
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
