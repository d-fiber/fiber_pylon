# Coding style

What the analyser cannot check, and what a reviewer will hold you to. The rules the
analyser does check are in `analysis_options.yaml` and are not repeated here.

## 1. Write like the file next to yours

Naming, splitting, the order of declarations, the way a failure is reported: match the code
you are joining, even where you would do it differently in an empty repository. A better
solution that is foreign to the code around it is still a worse one, because a reader loses
more crossing a convention mid-file than they gain from the new one.

## 2. Name the thing, not its category

`process`, `handle`, `doWork`, `data`, `result`, `obj` name nothing. Neither does a
`Manager`, `Helper`, `Utils` or `Service` suffix: it says the class has a category rather
than a subject. If no honest name comes, the thing has not been decided yet.

## 3. A function does the work its name promises, and nothing else

An honest name containing "and" means two functions. `validateAndSave` is two, and a caller
that only wanted to validate has no way to say so.

## 4. A side effect the name does not announce is a lie

A function that checks writes nothing. One that reads modifies nothing. The defect shows up
the day somebody calls it twice, and it does not look like its cause.

## 5. One level of abstraction per function

A function that orchestrates calls named steps. It does not open a file or concatenate a
query between two of them. The give-away is a reader's eye dropping from three lines of
domain vocabulary to one line of plumbing and back.

## 6. Past three parameters, a type is missing

And a boolean switch in a parameter list wants two named functions instead, because
`true` in last position teaches a reader nothing.

## 7. A class exposes what its name justifies

Read the name, then the members. A member that surprises belongs to another class. When no
name covers the whole list any more, the class holds two and wants cutting before a third
arrives.

A getter exists because the state it exposes belongs to the thing. A getter and a setter per
field, added by reflex, turn a class into a bag of data and scatter the logic that should
live inside it across every caller.

## 8. An object is valid as soon as it is built

Private fields, values that do not change unless something requires it, and no object that
has to be initialised in three calls in the right order.

## 9. The third use moves into the shared place

Two duplicates may be a coincidence, and a bad abstraction costs more than a duplication:
it is paid on every read and it comes apart badly. At the third it is not a coincidence.

What moves loses its context. If a shared function needs a parameter to tell its callers
apart, it is not shareable: those are two functions that resemble each other, and merging
them produces a body every new caller widens by one branch.

## 10. Every exported member carries a `///`

Including every field of an exported class, not only the interesting ones. A block where
two fields of five are documented reads as a claim that the other three have no unit, no
range, no provenance and no invariant, and the reader has no way to tell the genuinely
obvious field from the one nobody reviewed. So they distrust all five.

A field with nothing special to say says so in one short line. It costs a line and removes
the doubt from the four others.

## 11. A function body carries no comment

What you were about to write in the middle moves up onto the declaration, where the caller
sees it at autocompletion, which is where the question actually arises. A body is split,
moved and rewritten far more often than a signature, and a comment left in the middle
outlives the line it explained without anything signalling it.

A passage that needs explaining wants something else first: a named constant instead of a
literal, an extracted function whose name says what the comment would have, a type that
makes the intention checkable.

Analyser directives are not comments. They are instructions, they stay on the line they
govern, and they always give their reason.

## 12. A comment says why, never what

The what is already written underneath, and it will still be true when the comment has
stopped being. Say the real thing: the service that misbehaves, the case that breaks, the
consequence of doing it the other way.

```dart
// No.
/// Handles the edge case for robustness.

// Yes.
/// Renews ten minutes ahead of expiry, because a token that expires mid-call
/// costs a round trip and a replayed request, and the server only issues one
/// refresh token at a time.
```

## 13. A test file carries no comment

The name of the case and the assertion message carry the intention, and they are what shows
up when the suite is red. A comment appears nowhere at that moment, which is the only moment
anybody is reading the test.

## 14. Setup that needs explaining wants a name

A named builder function, a named constant instead of an obscure literal, a fixture named
after what it represents. Not a sentence above it.

## 15. Write the way you would say it out loud

Normal sentences with a subject and a verb, in comments, commit messages, test names,
assertion messages and log lines alike. Not a telegram, not a datasheet.

These never appear: an arrow used as a word, a decorative bullet, a dash standing in for a
conjunction, an emoji, an exclamation mark, capitals for emphasis, a drawn separator. A dash
keeps its ordinary uses, in a compound word, a range, or a markdown list item.

## 16. Say the real thing

Brochure vocabulary is out: robust, elegant, powerful, optimised, seamless, production
ready. So are the empty formulas that name nothing, such as "handles the logic" or "for
performance reasons".

The test is whether somebody who knows none of the context understands in one read. If they
have to read twice, the sentence is what needs fixing.

## 17. The source is in English

Code, identifiers, comments, logs, tests, and every document in this repository. Whatever
language the work happens in, nothing that lives in the source is translated.
