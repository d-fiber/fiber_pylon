# Tests

## 1. Running is not reading

A change is finished when it has run, not when it looks right. Rereading your own diff
proves nothing, because you read the intention you had rather than the code you wrote.

Three checks, cheapest first, and the third is the one that gets skipped:

- it analyses;
- the existing suite still passes, which says only that you broke nothing else;
- the path you just wrote was actually exercised.

`bash tool/test.sh` runs the first three of those. The last one is on you.

## 2. A test is written when its absence would let the problem come back

A defect gets one. A refusal, a limit or a rule gets one, because those paths are never
walked by ordinary use and nothing will announce the day they stop working. A pure function
with branches gives the best return there is, many cases for almost no setup. A behaviour
you have just decided gets one, so that the decision cannot be undone by accident.

None is needed when running says everything: a rename the compiler checks in full, a change
of wording, a move with no change of behaviour.

When in doubt, ask what will warn you if this breaks in six months. When the answer is
nobody, write the test.

## 3. Almost everything here is testable without a server

Pylon owns policy, and policy is exercised with fakes. There is no network in this suite
and there should not be one.

- An exchange plugged into `Credentials.renewWith` that returns a scripted sequence, or
  blocks on a `Completer`, is how renewal, deduplication and revocation are tested.
  `Credentials.forTesting` holds the credential in memory instead of the vault.
- `MockClient` from `package:http/testing.dart` answers `RestClient` without a socket.
- A `SocketLink` backed by a `StreamController` drives `SocketChannel`, including the cases
  a real server will not produce on demand: a link that goes quiet without closing, a join
  the server refuses, two opens at once.
- `MemoryKeyValueStore` and the credential's in-memory store stand in for storage.

If something can only be tested against a live server, that is usually a sign the seam is
in the wrong place.

## 4. A test you have never seen fail proves nothing

See it red before you see it green. A test written after the fix, passing on the first run,
has demonstrated nothing and may be asserting nothing at all.

Written afterwards it also tends to describe the behaviour observed rather than the
behaviour wanted, bug included, because the output gets copied into the expectation. Decide
the expected value before looking at the result.

## 5. When a test goes red, the code is wrong until proven otherwise

Adjusting the expectation removes the only warning you had. Look at the code first.

## 6. Time is a parameter, not a wait

Anything with a timer takes its durations as arguments, so a test can ask for milliseconds
where production asks for minutes. A test that sleeps for a real second to prove a timeout
is a slow test and a flaky one.

Where a delay is unavoidable, keep it small and give the assertion room: a timer set at
20 ms is checked after 50, not after 21.

## 7. Attach the error handler before the error can fire

A future that completes with an error and has no listener at that moment is reported as
unhandled, and the test fails for a reason that has nothing to do with what it was testing.

```dart
// No: the error fires while nothing is listening.
final pending = guard.share(call, key: 'brand/7');
blocked.completeError(const Fault(Signal.missing));
await expectLater(pending, throwsA(isA<Fault<Signal>>()));

// Yes: expectLater attaches straight away.
final pending = expectLater(
  guard.share(call, key: 'brand/7'),
  throwsA(isA<Fault<Signal>>()),
);
blocked.completeError(const Fault(Signal.missing));
await pending;
```

## 8. The name of the case and the assertion message are the whole documentation

They are what appears when the suite is red, and a test file carries no comments. Name the
case after what must be true, not after the method being called:

```dart
// No.
test('share works', ...);

// Yes.
test('hands a shared answer to every caller that joined', ...);
test('leaves a refused name unconfirmed instead of assuming it worked', ...);
```

## 9. Setup that needs explaining wants a name

A named builder, a named constant instead of an obscure literal, a fixture named after what
it represents. Not a sentence above it, which nobody reads when the suite is red.

## 10. Take away what you made to test

Directories, sample projects, temporary files, entries slipped somewhere to see what would
happen. All of it goes once the check is done, or it becomes a state somebody will
eventually mistake for real.

Remove it while looking at what you remove. Never delete a pattern.

## 11. Say what you ran, and say what you did not

Report the command and its real output. A failure described from memory has lost exactly
the detail that would have explained it.

When part of the work could not be exercised, for want of a service or a platform, say so
with the reason and name what is left to check.

## What runs it

```
bash tool/test.sh
```

Resolve, analyse, check the formatting, run the suite. The CI runs the same script, plus
the licence headers, the commit messages and the version.
