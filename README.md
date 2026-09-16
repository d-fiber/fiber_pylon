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

**The barrier**, which a port touches: `RestNode` and `RestEndpoint` for a REST call,
`RealtimeNode` and `RealtimeTopic` for a live one, `Result`, `Fault`, `FaultMapper`, `Sdk`,
`Singleton`, `Config`. This is what a service layer sees, and it does not change when the
backend does.

**The toolkit**, which only an `Sdk` implementation sees, wiring a `RestNode` or
`RealtimeNode` to a real server: `RestClient`, `CredentialManager`, `CallGuard`,
`SocketChannel`, `ChannelKeeper`, `HealthMonitor`, `Preference`, `KeyValueStore`,
`Observable`, `Reporter`, `Backoff`. Each is a mechanism every backend would otherwise
rewrite, and rewrite worse the second time.

`package:fiber_pylon/fiber_pylon_io.dart` carries the one piece that needs `dart:io`, a `SocketLink`
over a WebSocket. It is separate so that importing pylon does not stop a project from
compiling for the web.

## Composing a call

A port never builds a `RestRequest` or a path string by hand. It composes a `RestNode`,
rooted once on the `Sdk` implementation's own `RestClient`:

```dart
final api = RestNode<AdminSignal>.root(client).node('v1');
final brand = api.node('brand');

Future<Result<Brand, ReadBrandError>> read(String id) => brand
    .value(id)
    .url()
    .get(mapper: readBrand, decode: Brand.fromResponse);
```

`node` takes a literal this SDK's own author writes once, such as `'brand'`, and `value`
takes a value that came from somewhere else — a caller, a deep link, a server. The two are
never interchangeable: a literal may carry several segments separated by `/`, because
nothing external ever reaches it, while a value is always exactly one opaque,
percent-encoded segment, whatever it contains. Interpolating an external value straight
into a path string, the shape it is easiest to reach for, lets it change which resource a
call actually reaches, or even escape the branch it was meant to stay under.

Only `url` closes the chain into a `RestEndpoint` that can carry a verb; composing never
talks to the network. `RealtimeNode` and `RealtimeTopic` do the same for a live connection:

```dart
final realtime = RealtimeNode<RealtimeEvent>.root(
  keeper: keeper,
  name: (segments) => segments.join(':'),
  belongsTo: (event, topic) => event.topic == topic,
);

Stream<BrandChanged> watch(String id) => realtime
    .node('brand')
    .value(id)
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

What stays outside is every judgement the protocol does not make: which statuses are
failures, what an error body looks like, how a call is authenticated, which failure
deserves a renewal. Each of those is asked for.

## Where the boundary actually is

It is `Fault`, and what makes it work is that pylon never reads it. A fault carries a
signal from the adapter's own vocabulary, an enum the adapter declares.

```dart
enum AdminSignal {
  unauthorized, forbidden, vpnRequired, notFound,
  tooManyRequests, noRoute, timedOut, nameEmpty, duplicateCall, unknown,
}

throw const Fault(AdminSignal.nameEmpty);
```

Pylon offers no list of failure kinds, because any list would be a guess about the projects
it has not met. `unauthorized` does not mean the same thing everywhere, and in a system
with no authentication it means nothing at all.

A `FaultMapper` turns that signal into the error one operation declares. Both sides of the
table are typed, so a member that does not exist does not compile and a rename is caught
rather than discovered at runtime.

```dart
const createBrand = FaultMapper<AdminSignal, CreateBrandError>(
  signals: {
    AdminSignal.unauthorized: CreateBrandError.unauthorized,
    AdminSignal.forbidden: CreateBrandError.notPermitted,
    AdminSignal.vpnRequired: CreateBrandError.vpnRequired,
    AdminSignal.tooManyRequests: CreateBrandError.tooManyRequests,
    AdminSignal.noRoute: CreateBrandError.networkError,
    AdminSignal.nameEmpty: CreateBrandError.nameEmpty,
  },
  fallback: CreateBrandError.unknown,
);
```

The table belongs next to the adapter, not to the contract, because it is the translation
of one server's vocabulary. Swapping servers means writing new tables beside the new
adapter; the contract, and everything above it, does not move.

Wherever pylon has to act on a failure it is handed a set of signals rather than left to
interpret one. `CredentialManager` is told which signals mean the credential is dead,
`CallGuard` which are worth renewing for, and even the refusal `CallGuard` issues for a
duplicate call is named by you.

## The REST client

`RestClient` is the whole of what makes a backend a REST backend: a base URL, a way to name
failures, and the headers to carry.

```dart
final client = RestClient<AdminSignal>(
  baseUrl: Uri.parse('https://admin.example.test/v1/admin/'),
  classifier: const AdminClassifier(),
  guard: guard,
  headers: (request) async => {
    if (credentials.credential case final session?)
      'authorization': 'Bearer ${session.accessToken}',
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

The classifier is the only place in a REST adapter that reads a status code.

```dart
class AdminClassifier implements RestClassifier<AdminSignal> {
  const AdminClassifier();

  @override
  AdminSignal? ofResponse(RestResponse response) {
    if (response.status >= 200 && response.status < 300) return null;

    final body = response.body;
    final code = body is Map<String, dynamic> ? body['code'] : null;
    if (code == 'vpn_required') return AdminSignal.vpnRequired;

    return switch (response.status) {
      401 => AdminSignal.unauthorized,
      403 => AdminSignal.forbidden,
      429 => AdminSignal.tooManyRequests,
      _ => AdminSignal.unknown,
    };
  }

  @override
  AdminSignal ofTransport(Object error, StackTrace stackTrace) =>
      error is TimeoutException ? AdminSignal.timedOut : AdminSignal.noRoute;
}
```

Even `status >= 400` is not supplied. It looks universal until it meets the API that
answers `200` with an error payload, or the one where `404` is an ordinary answer meaning
the resource does not exist yet. Both exist, and both are entitled to say so here.

## Credentials

Pylon does not define what a session is. The credential is your own type, opaque, and the
only things the renewal policy needs to know are asked for.

```dart
final credentials = CredentialManager<Ticket, AdminSignal>(
  store: StoredCredential<Ticket>(
    preferences,
    key: 'ticket',
    encode: (ticket) => ticket.serialise(),
    decode: Ticket.parse,
  ),
  refresher: AdminRefresher(),
  expiresAt: (ticket) => ticket.expiresAt,
  fatalSignals: {AdminSignal.unauthorized, AdminSignal.forbidden},
);
```

The backend writes `refresh(current)` and nothing else. The rest is policy, and it is the
same everywhere: renew ahead of expiry rather than after a call has already failed,
collapse simultaneous attempts into one exchange so a screen firing six requests does not
burn six refresh tokens, keep a failed attempt pending instead of dropping it, and revoke
on the signals it was told mean the credential is dead.

`fatalSignals` has no default on purpose. Pylon cannot know which of an adapter's signals
means the credential was rejected rather than that the server was unreachable, and getting
it wrong is expensive in both directions: too wide a set signs people out during an outage,
too narrow a one leaves them retrying a credential that is gone.

A project with no notion of a credential never builds one of these. Nothing else requires
it.

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

A `RestEndpoint` derives both by default (`CallKey.derived()`, the default for every verb):
a read's share key folds in its path, its sorted query and whether it is authenticated; a
mutation's deduplication key folds in the same plus a canonicalised JSON body, so two
creations with different content never block each other while a double submission of the
same one does. `RestRequest` refuses a call carrying both a share key and a deduplication
key at once, so a call whose real semantics differ from its verb — a paginated read exposed
as a `POST` because of a filter body too complex for a query string — says so explicitly
with `CallKey.share(...)` rather than fighting that constraint by hand.

## Realtime

`SocketChannel` carries the policy, `SocketProtocol` carries the frames. The split is the
same one as between `RestClient` and `RestClassifier`: moving to another server means
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

## What is deliberately absent

No token format, no notion of a session, no list of error kinds, no envelope around a
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
