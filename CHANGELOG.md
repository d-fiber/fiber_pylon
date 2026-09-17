# Changelog

## 2.0.0

BREAKING:

- [BREAKING]: split lib/src into barrier/toolkit, rename Backend to Sdk (4a5439c)

DEV:

- [DEV]: rewrite RealtimeNode to mirror RestNode's path and parameters (568bd07)
- [DEV]: redesign RestNode and RestCall, merge FaultResolver into Fault (2dc507b)
- [DEV]: rewrite the example around a PostsSdk facade, groundsdk style (8e4e602)
- [DEV]: give value equality to Result, Fault, and the other data types (c0df3ed)
- [DEV]: add MemoryChannel, a fake Channel with no server behind it (996bea5)
- [DEV]: compose REST and realtime calls through a node chain (eb535bc)

REFACTO:

- [REFACTO]: rename Singleton's assign/isSet/release to initialize/isInitialized/dispose (f833921)
- [REFACTO]: rename Config to Configuration, Requirement to EnvironmentVariable (a9f7011)

## 1.0.0

DEV:

- [DEV]: lay down the primitives, the suite and the CI (8a965e4)
