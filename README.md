# pylon

The wall between a project and the REST API answering it right now.

Pylon exists so that unplugging one REST API and plugging in another changes one line of
wiring and nothing else. It is built on one refusal: **pylon understands neither side.** It
does not know what your resources are, what your credentials look like, or what can go
wrong. It knows how to let something through, or not.

Everything here is therefore either a shape you fill in, or a policy that is identical
whatever fills it in. Nothing infers, nothing recognises a name, nothing assumes a format.
Where a decision belongs to you, it is a required argument, never a default that happens to
be right most of the time.

## The two halves

**The barrier**, which a port touches: `RestNode`, `RestPath`, `RestParameters` and
`RestCall` for a REST call, `RealtimeNode`, `RealtimePath`, `RealtimeParameters` and
`RealtimeTopic` for a live one, `Result`, `Fault`, `Sdk`, `SdkType`,
`BackendSdk`, `RestBackendSdk`, `LocalBackendSdk`, `VendorBackendSdk`,
`Configuration`. This is
what a service layer sees, and it does not change when the backend does.

**The toolkit**, which only an `Sdk` implementation sees, wiring a `RestNode` or
`RealtimeNode` to a real server: `RestClient`, `Credentials`, `CallGuard`,
`SocketChannel`, `ChannelKeeper`, `PreferencesStorage`, `SecureStorage`, `LocalDatabase`,
`Database`, `Observable`, `Reporter`, `Backoff`. Each is a mechanism every backend would otherwise rewrite, and rewrite worse the
second time.

`package:fiber_pylon/fiber_pylon_io.dart` carries the one piece that needs `dart:io`, a `SocketLink`
over a WebSocket. It is separate so that importing pylon does not stop a project from
compiling for the web.

## Composing a call

A port never builds a `RestRequest` or a path string by hand. It composes a `RestNode`,
rooted once on the `Sdk` implementation's own `RestClient`:

```dart
final api = RestNode(client).path((p) => p.segment('v1'));
final brand = api.path((p) => p.segment('brand'));

Future<Result<Brand, ReadBrandError>> read(String id) async {
  try {
    final response = await brand
        .path((p) => p.parameter('id'))
        .parameters((p) => p.parameter('id', id))
        .get()
        .send();
    return OK(Brand.fromResponse(response));
  } on Fault catch (fault) {
    return Failure(readBrandError(fault));
  }
}
```

`path` receives an empty `RestPath` and returns the one it composed, through
`RestPath.segment` for text this SDK's own author writes once, such as `'brand'` or
`'brand/reviews'`, and may carry several segments separated by `/`, because nothing
external ever reaches it. `RestPath.parameter` names a placeholder instead, resolved later
by `parameters`, through `RestParameters.parameter`, once a caller actually has the value —
a caller, a deep link, a server. Each one becomes exactly one opaque, percent-encoded
segment, and `parameters` refuses to resolve if what it is given does not match the
placeholders exactly. Interpolating an
external value straight into a path string, the shape it is easiest to reach for, lets it
change which resource a call actually reaches, or even escape the branch it was meant to
stay under; a parameter, which is never a raw string a caller could shape, closes that off
at compile time rather than by convention.

Any node can carry a verb directly; there is no separate step that closes composing before a
call can go out. A node still carrying an unresolved parameter throws the moment a verb is
called on it, rather than sending a path with a placeholder still in it. `RealtimeNode`
mirrors the same `path` and `parameters`, closing into a `RealtimeTopic` instead of a verb:

```dart
final realtime = RealtimeNode<RealtimeEvent>.root(
  keeper: keeper,
  name: (segments) => segments.join(':'),
  belongsTo: (event, topic) => event.topic == topic,
);
final brand = realtime.path((p) => p.segment('brand').parameter('id'));

Stream<BrandChanged> watch(String id) => brand
    .parameters((p) => p.parameter('id', id))
    .topic()
    .events
    .map(BrandChanged.fromEvent);
```

`RealtimeTopic.events` joins on the first listener and leaves on the last, shared across
every caller that composes the same name: two screens watching the same brand at once make
one join on the wire, and the topic is left only once both have stopped listening.

## The one thing pylon assumes

That both ends of the swap are REST. `RestClient` speaks HTTP and `RestMethod` is a closed
list, because those are a protocol's own words rather than a guess about a project.

What stays outside is every judgement the protocol does not make: what an error body looks
like and how a call is authenticated. Each of those is asked for, or read from the fault by
the operation that wants it.

## Where the boundary actually is

It is `Fault`, and what makes it work is that pylon never names a failure. A fault carries the
status the server answered and the body it sent, or, when a call got no answer, the exception
it failed with.

```dart
throw const Fault(status: 404);                          // the server answered
throw Fault(cause: TimeoutException('waited too long')); // no answer: no status, the cause says why
```

`RestClient` throws one for any response outside `200` to `299`, with the `status` and the
decoded body in `fault.details`, and one with the exception the http stack threw when nothing
came back. What a `401` or a `TimeoutException` means is for the operation to say.

Each operation declares its own error enum, complete, and writes the `switch` that turns a fault
into one of its members. Both sides are typed, so a member that does not exist does not compile
and a rename is caught rather than discovered at runtime. Two operations that fail the same way
list it twice, on purpose: neither depends on the other.

```dart
enum CreateBrandError {
  unauthorized, notPermitted, vpnRequired, tooManyRequests, nameEmpty, serverDown, timedOut, offline, unknown,
}

CreateBrandError resolve(Fault fault) {
  final code = fault.details is Map ? (fault.details as Map)['code'] : null;
  return switch (fault.status) {
    401 => CreateBrandError.unauthorized,
    403 when code == 'vpn_required' => CreateBrandError.vpnRequired,
    403 => CreateBrandError.notPermitted,
    429 => CreateBrandError.tooManyRequests,
    400 when code == 'name_empty' => CreateBrandError.nameEmpty,
    final int status when status >= 500 => CreateBrandError.serverDown,
    null => fault.cause is TimeoutException ? CreateBrandError.timedOut : CreateBrandError.offline,
    _ => CreateBrandError.unknown,
  };
}
```

A port calls it itself, from its own `catch`, as `read` does above: `RestNode` never sees it
and never decides which failures a port distinguishes. A raw exception is a bug and is left to
propagate rather than quietly becoming an error nobody named.

Wherever pylon has to act on a failure it is handed a set of statuses. `Credentials.renewWith`
is told which mean the credential is dead, and `CallGuard` which are worth renewing for.

## The REST client

`RestClient` is the whole of what makes a backend a REST backend: a base URL and the headers
to carry.

```dart
final client = RestClient(
  baseUrl: Uri.parse('https://admin.example.test/v1/admin/'),
  guard: guard,
  headers: (request) async => {
    if (Credentials.value case final credential?)
      'authorization': 'Bearer ${credential.token}',
    'x-app-key': appKey,
  },
);

final response = await client.send(
  RestRequest(path: 'brand/$id', shareKey: 'brand/$id'),
);
final brand = response.map['data'];
```

The body is not unwrapped. An envelope like `{"data": ...}` belongs to one server's
conventions, so an adapter reads `response.map['data']` itself rather than pylon deciding
that every server has an envelope.

A response outside `200` to `299` throws a `Fault` named by its status, as above, and a call
that never reached the server throws one too. Nothing else is thrown, so a port catches a
single type.

## Credentials

One singleton answers everybody: `Credentials`. A screen, the local database and the REST
client all ask it, from anywhere, and everything behind it stays internal.

```dart
await Credentials.set(Credential(token: 'abc', refreshToken: 'again', expiresAt: expiry));

Credentials.isHeld;                        // is there one?
Credentials.value?.token;                  // what a call carries
Credentials.held.stream.listen(route);     // follow a sign-in and a sign-out
Credentials.stream.listen(reconnect);      // the credential now, then each one that replaces it
Credentials.isStale;                       // within minutes of expiry: a renewal is due

await Credentials.clear();                 // signing out
```

It reads like a `Preference`: `value` and `stream`, and `set` and `clear` write.
A `Credential` is one opaque `token`, and pylon never looks inside it. The rest is optional
and says only what renewing takes: a `refreshToken`, an `expiresAt`, and a `holder`, the
account it belongs to.

It is kept in the operating system's vault through `SecureStorage`, never in the
preferences: a token in `PreferencesStorage` sits in a file anyone can copy off the device.
It is found again before `configureSdk` returns, so nobody ever asks it a question it
cannot yet answer, and `held` moves only on a sign-in or a sign-out, never on a renewal.

### Renewing

The backend writes one function, the exchange, and plugs it in once, right after
`configureSdk`:

```dart
Credentials.renewWith(
  refresh: (current) => api.exchange(current.refreshToken!),
  fatalStatuses: {401, 403},
);
```

The rest is policy, and it is the same everywhere: renew ahead of expiry rather than after
a call has already failed, collapse simultaneous attempts into one exchange so a screen
firing six requests does not burn six refresh tokens, keep a failed attempt pending instead
of dropping it, and clear the credential on the statuses it was told mean it is dead. The
exchange throws a `Fault` naming what went wrong. A credential without a `refreshToken` is
held and never renewed.

`fatalStatuses` has no default on purpose. Which refusal means the credential was rejected
rather than that the server was unreachable depends on the backend, and getting it wrong is
expensive in both directions: too wide a set signs people out during an outage,
too narrow a one leaves them retrying a credential that is gone.

### The local database

```dart
await configureSdk();
Tenant.follow();
```

Isolated tables then hold the account the credential names as its `holder`, the anonymous
rows after a sign-out, and the previous account's never. A listener of `stream` has run
before `set`, `clear` or a renewal returns, so once `held` moves the tenant is already the
right one.

### The REST client

```dart
final guard = CallGuard.renewing(renewOn: {401});
```

Every authenticated call renews ahead of expiry, replays once after a renewal, and clears
the credential when the replay is refused too. `RestClient`'s `headers` reads
`Credentials.value`, so the token it sends is the one just renewed.

The calls a `Repository` makes carry the credential unless its `requiresCredential` is `false`, and
the ones the exchange given to `Credentials.renewWith` makes never do. Nothing is marked on the
node: the call that signs in is a repository like any other, with `requiresCredential` set to
`false`.

A project with no notion of a credential never sets one. Nothing else requires it.

## Calls that collide

Two calls that would collide are handled in one of two ways, and they are not
interchangeable.

`dedupKey` **refuses** the second, which is what protects a mutation from being submitted
twice. `shareKey` **joins** it to the first and hands both the same answer, which turns six
widgets asking for the same resource into one request. A read wants the second, a creation
wants the first, and only the caller knows which it is.

```dart
client.send(RestRequest(path: 'brand/$id', shareKey: 'brand/$id'));

client.send(RestRequest(
  path: 'brand',
  method: RestMethod.post,
  body: payload,
  dedupKey: 'create-brand',
));
```

A shared key is released as soon as the call settles, so this coalesces what overlaps in
time and caches nothing.

A `RestCall`, composed through a `RestNode`, always derives one of the two, for every verb,
with no way to opt out. The key folds in the path, the sorted query parameters, the sorted
headers, whether it is sent for a repository that requires no credential, the canonicalised JSON
body, the form fields and the
files — whichever of those a given call actually set, since every verb accepts all of them.
Two creations with different content never block each other, while a double submission of
the same one always does, however many times it is fired. A `RestNode.get` or `RestNode.head`
call shares that key; every other verb refuses a second call under it instead of sending it.

## Realtime

`SocketChannel` carries the policy, `SocketProtocol` carries the frames. The split is the
same one as between `RestClient` and its headers: moving to another server means
writing the protocol, and nothing else.

```dart
final channel = SocketChannel<RealtimeEvent>(
  protocol: PhoenixProtocol(credentials, appKey),
  opener: WebSocketLink.opener(),
);
final keeper = ChannelKeeper(channel);
await keeper.start();
await keeper.join('admins');
```

What the policy holds is exactly what a socket gets wrong.

**A link that died without saying so.** A connection that drops silently, and they very
often do when a network changes underneath, leaves a socket that reports nothing: no close,
no error, no frames. Waiting for a close that will never come is how an app sits there
looking connected and receiving nothing. `SocketChannel` sends a heartbeat every
`heartbeatInterval` and gives up on the link if nothing at all arrives for `silence`,
because traffic is the only evidence a link is alive.

**A subscription that was refused.** A server that turns down a join usually says so in a
frame nobody reads, and the result looks exactly like a quiet topic. Here a refusal is
reported and the name is not recorded: `channel.confirmed` holds only what the server
confirmed.

**Two connections at once.** Opening while an open is already under way is easy to do from
a reconnect timer and a credential change arriving together, and it leaves an orphaned
socket whose frames still arrive. Opening is single-flight.

Reconnecting and rejoining are not here: that is `ChannelKeeper`, which already holds them
for every kind of channel, with a jittered backoff.

## The local database

Everything stored on the device goes through one SQLite file, named after the app in snake
case (`my_app.db` for an app called `MyApp`), opened once by `configureSdk()` and kept open
for as long as the app runs. `LocalDatabase` is that one database: a project calls its static
methods and never creates another. Three things sit on it, and each is one decision.

### The file

Every launch checks it first. A missing file is created, a readable one is used as it is,
and one that cannot be read or fails `PRAGMA quick_check` is deleted and created again: its
content is lost, since nothing in it can be read.

It is **encrypted** with SQLCipher, by a key derived from the app's own `Fingerprint`, so a
copy of the `.db` taken off the device cannot be read. The fingerprint is 256 random bits,
created the first time the app runs and kept in the operating system's vault (Keychain,
Keystore). Nothing hands it out: what leaves it is derived from it, one derivation per
purpose. A vault that fails, or holds something that is not a fingerprint, stops the launch
instead of minting a new one, since that would orphan the file.

- SQLCipher exists on **Android, iOS and macOS** only. `LocalDatabase.encryption` says what to do
  elsewhere: `EncryptionPolicy.whenAvailable` (the default) leaves the file in clear and
  `LocalDatabase.isEncrypted` says so; `required` refuses to start; `off` never encrypts.
- A database in clear that is already there is never deleted to encrypt over it: the launch
  stops with a message, so that nothing is lost silently.
- What this guarantees is that the secret cannot be guessed and is in no file. It does not
  stop code running inside the app from asking for a derivation, and a device whose vault
  gives way loses the fingerprint with it.
- The encryption itself is SQLCipher's, which the test suite does not have on the desktop: it
  is checked on a device, and the tests prove what surrounds it.

### The secrets

`SecureStorage` is the operating system's vault as typed entries, in the same style as
`PreferencesStorage`: registered by `configureSdk()`, first of everything, and reached through static
factories without holding a reference of its own.

```dart
class AppSecrets {
  late final refreshToken = SecureStorage.string_('refresh_token', '');
  late final pin = SecureStorage.bytes_('pin_hash', Uint8List(0));
}

await AppSecrets().refreshToken.set(token); // in the vault first, then the entry changes
final token = AppSecrets().refreshToken();  // answered at once, from what was read at launch
```

The entries are `string_`, `bytes_`, `int_` and `bool_`, each with a default and a stream, and a
write that the vault refuses leaves the entry as it was. The app's fingerprint is held by the same
storage, as `SecureStorage.fingerprint`, and is not an entry: it cannot be read, replaced or
cleared through one. Keys that start with `pylon.` are the package's own.

### The tables

A table is declared once, as a class, and the engine creates it, adds the columns it gained,
and reads and writes it typed:

```dart
final class UsersTable extends KeyedTable<User, String> {
  UsersTable() : super('users');

  late final id = column.text('id').primaryKey();
  late final name = column.text('name');
  late final age = column.integer('age');

  @override
  Tunnel get tunnel => Tunnel.isolated;

  @override
  List<Field<Object?>> get columns => [id, name, age];

  @override
  User read(Reader row) => User(id: row(id), name: row(name), age: row(age));

  @override
  List<Assignment> write(User user) => [id.to(user.id), name.to(user.name), age.to(user.age)];
}
```

Every filter, order and update is written with the table's own columns:
`usersTable.age.isGreaterThan(18)`, `usersTable.name.asc()`, `usersTable.age.incrementBy(1)`. A
value of the wrong type, or a column that does not exist, does not compile. Comparisons that
need an order exist only on types that have one.

Reads can be **watched**: the same query as a stream that sends the rows now, and again after
each write that changes them — an insert, an update, a delete, a batch, a committed
transaction, never a rolled back one.

### The database layer

`Database` puts those tables behind SQL's own words (`from`, `where`, `orderBy`, `limit`,
`select`, `insert`, `upsert`, `update`, `delete`), with no query language of its own:

```dart
final class OwnDatabase extends Database {
  final users = UsersTable();

  @override
  List<KeyedTable<Object, Object>> get tables => [users];
}

await OwnDatabase().initialize(); // once, after configureSdk()

final db = Database.instance<OwnDatabase>(); // from anywhere afterwards
await db.from(db.users).upsert(const User(id: 'ada', name: 'Ada', age: 36));
await db.from(db.users).where(db.users.id.isEqualTo('ada')).update([db.users.age.incrementBy(1)]);
final adults = await db
    .from(db.users)
    .where(db.users.age.isGreaterThanOrEqualTo(18))
    .orderBy((o) => o.asc(db.users.name))
    .select();
db.from(db.users).stream().listen(print);
```

`from(table)` opens the rows of a table. It reads with `where`, `orderBy`, `limit`, `offset`,
`select`, `first`, `count`, `exists` and `stream`, and writes with `insert`, `upsert`, `update`,
`delete`, `get(key)` and `remove(key)`. `db.batch()` queues `insert`, `upsert`, `update` and
`remove`, then `commit()` applies them together or not at all, and `db.runTransaction` hands
over a `Transaction` with the same `from`. What is specific to typed SQLite on one device:

- A row has a column per field. There are no free-form nested documents, and no `arrayUnion`
  or `arrayRemove` on an array: a list is a column of its own, written whole.
- `incrementBy` is done by the database in one statement, on a numeric column.
  A server timestamp is `column.to(DateTime.now())`, the device's clock.
- Tables are flat: no sub-collections, no group queries.
- `runTransaction` applies each write at once and never retries: SQLite runs one transaction at
  a time, so there is no conflict to retry.
- A `stream` sends the rows again, not what changed in them. It hears writes made through the
  engine; a write from another process, or another connection on the same file, is not heard.

### Accounts: two mechanisms that do not mix

An app with sign-in must not show one account what another saved on the same device, and
sometimes it does want to see everything. Those are two mechanisms, and nothing lets one slip
into the other.

**The tenant mechanism** is what a table's `tunnel` chooses, and what `Tenant` drives:

```dart
Tenant.use(account.id); // on sign-in
Tenant.leave();         // on sign-out
```

- `Tunnel.isolated` gives every tenant rows of its own. The same key under two tenants is two
  rows, and neither can read, list, count or overwrite the other's. The engine adds the tenant
  to every read and write, so no call can forget it, and the key, the unique columns, the
  indexes and the foreign keys between isolated tables are per tenant too: a row can never
  point at another tenant's. Without a current `Tenant`, an isolated table holds the anonymous,
  signed-out rows; leaving an account never brings its rows back into view.
- `Tunnel.shared` (the default) keeps one copy for everyone, whichever tenant is current.
- An operation finishes on the tenant it started on even if `Tenant.use` is called meanwhile, a
  batch and a transaction keep to the one that was current when they began, and a watched
  query is handed the new tenant's rows from scratch, never the previous one's.
- `db.adoptAnonymousRows()` carries what was saved before signing in over to the account that
  just did, and `db.purgeCurrentTenant()` deletes the account's rows. Neither reads or touches
  another tenant's.
- Nothing in this mechanism reaches another tenant: not a row, not a count, not the name of a
  tenant. `Tenant.current` is not remembered across launches; the project that knows who is
  signed in calls `Tenant.use` at startup. Changing the tunnel of a table that already holds
  rows needs a migration.

**The whole-database mechanism** is a separate entry point that reads every tenant, and it is
only opened by the app's fingerprint:

```dart
final everything = db.users.onWholeDatabase(SecureStorage.fingerprint); // reads and edits across tenants
final whole = db.wholeDatabase(SecureStorage.fingerprint);
await whole.tenants();                       // every tenant that holds rows
await whole.transfer(from: 'a', to: 'b');    // move one tenant's rows to another
await whole.purge('a');                      // delete one tenant's rows
```

Any other fingerprint is refused, and so is a database that was opened without one. The raw
calls of `LocalDatabase` — `execute`, `insert`, `query`, `rawQuery`, `update`, `delete`,
`transaction`, `batch`, `tableExists`, `tableNames`, `columns`, `checkpoint` — read the whole
database too, and present the app's fingerprint themselves: `LocalDatabase.rawQuery(sql)`.

The rest of the engine — the schema DSL, the migrations, the drift report — is the package's
own plumbing and is not exported. `LocalDatabase` cannot be built by hand either: only its
static calls are for a project.

## The network

`Network` answers whether the network can be reached, from anywhere, the way `Credentials`
answers whether it holds a credential.

```dart
Network.isReachable.value;                     // can it be?
Network.isReachable.stream.listen(showBanner); // the answer now, then every change
```

It is what the operating system reports (through `connectivity_plus`): a network interface
that is up, not a server that answers. A device on a wifi that reaches nothing is reachable
here, and the request over it fails on its own. Pylon does not probe a host of its own
choosing, since no host is right for every project, and when the platform cannot say the
answer is reachable: nothing is refused on a guess.

## Repositories that read the cache

A screen never reads the network. It reads the local database, and a refresh only brings the
database up to date. `Repository` is where it reads: a small class a project writes per
piece of data it shows, with its parameters in its own fields.

```dart
final class UsersList extends Repository<List<User>, List<User>, UsersError> {
  @override Future<List<User>> fetch() => RestGroundSdk.I.users.list();            // the network
  @override Future<void> response(List<User> users) => ...;                        // the database
  @override Stream<List<User>> stream() => db.from(db.users).stream();              // the only local read: what it holds, then every change
  @override UsersError resolve(Fault fault) => ...;   // a switch over fault.status and fault.cause
}

final users = GroundSdk.I.users.list();   // a repository, made where the screen needs it
users.data.value;                     // what is stored: null until the database has answered, or when it holds nothing
users.data.stream.listen(show);       // the value now, then every change
await users.refresh();                // fetch, then response: the database moves, so does the stream
```

A repository stands for one piece of data, so what identifies it is in its own fields, fixed
when it is made: `AdultsList(minAge: 18)` and `AdultsList(minAge: 65)` are two repositories,
and each one's `fetch`, `stream` and `response` read the same `minAge`, so what is
asked of the network is what is read from the database. When a parameter changes while the
screen is open, make another repository and `dispose` the first.

One way only: `refresh` writes, the database's own `stream` emits, `data` follows. There is no
second source for a screen to reconcile with the first, and a change of tenant swaps what
`data` holds along with the rows. `data` is an `Observable`, the way a `Preference` reads:
`value` and `stream`. There is no initial value to invent or to read: the repository listens to
`stream()` right after it is made, and that stream's first event is what the database holds. So
a screen that asks later finds the value already in `data`, and one that asks within the first
moments gets `null`, then the value. `data` is also `null` when the database holds nothing.

A repository that `requiresCredential` listens to the database only while a credential is held: it
starts when someone signs in, and when they sign out it stops listening and empties `data`,
without being disposed, and it starts again at the next sign-in. A refresh made without a
credential ends `StatusUnauthenticated`.

What is happening is a second observable, `status`, and it is independent of the first: when a
refresh fails or the network is out, `data` still holds what is stored.

`status` is a signal more than a state. It starts as `StatusRunning`, while `data` loads what
the database already holds, and then every outcome is announced once, to whoever follows
`status.stream`, and the status is `StatusIdle` again at once: `Running`, `Succeeded`, `Idle`
for a refresh that went through, `Running`, `Failed(error)`, `Idle` for one that did not. Two
states do not let go at once. `StatusRunning` lasts until what it is doing is done, and only
then does the outcome replace it. `StatusOffline` lasts until the connection is back, for a
repository that requires a connection: it watches `Network`, answers a `refresh` without a request
while it says the network is out, and goes idle when it says it is back. A repository that does
not require a connection never ends offline: it tries the request, and a failure is a
`StatusFailed` with the error `resolve` chose.

```dart
users.status.stream.listen((status) => switch (status) {
  StatusRunning() => showSpinner(),
  StatusOffline() => showBanner('no network, showing what is stored'),
  StatusUnauthenticated() => showSignIn(),
  StatusFailed(:final error) => showError(error),
  StatusSucceeded() || StatusIdle() => hideBanner(),
});
```

The variants are only what pylon can decide by itself: the life of the refresh, whether a
credential was held to make it (`requiresCredential` and `Credentials`), and whether the network
was reachable (`Network`).

Two settings say what a repository is, and both are `true` unless it overrides them.
`requiresCredential` says it reads an account's data and carries the credential. `requiresConnection`
says a refresh looks at the connection before asking: a REST read wants that, since with no
connection there is nothing to ask, and it ends `StatusOffline` without a request. A REST write
overrides it to `false`, since the request is worth trying and its own failure is the honest
answer, and so does a call to a vendor's package over bluetooth or a local network, which needs no
internet at all. A request that signs someone in overrides `requiresCredential` to `false`.

Everything else is the project's own error `E`, an enum that lists every way this repository
can fail. `resolve` produces it from the fault with a `switch` over `fault.status` and `fault.cause`: that is where
a project says that a request which never reached the server means the network.

Six screens asking at once make one request: a `refresh` under way is joined. An error that is
not a `Fault` is a bug and propagates.

## What is deliberately absent

No token format, no notion of a session, no envelope around a
response body, no rule about which status means what, no frame format, no environment
reading, no code generation. Every one of those belongs to one server rather than to REST,
and a wall that took a side would stop being a wall.

No automatic retry, no request cancellation, no response cache, no offline queue either.
Each would either duplicate a tool the Dart ecosystem already publishes
(`package:async`'s `CancelableOperation` covers cancellation), or answer a question this
cannot: whether a given call is safe to repeat, how long an answer stays valid, or what
"offline" should mean for one particular resource. Those belong one layer up, next to the
call that actually needs them.

## Verifying

```
bash tool/test.sh
```

That resolves, analyses, checks the formatting and runs the suite, which is what the CI
runs too.

## Licence

Mozilla Public License 2.0. See `LICENSE`, and `CONTRIBUTING.md` for what that means in one
paragraph.
