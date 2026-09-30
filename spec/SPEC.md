# CSIL Node Packaging Specification

| Version   | 1.0.0      |
| --------- | ---------- |
| Published | 2026-09-30 |

## Contents

- [Requirements language](#requirements-language)
- [Terminology](#terminology)
- [1. Scope](#1-scope)
  - [1.1 Versioning and compatibility](#11-versioning-and-compatibility)
- [2. Simulation node model](#2-simulation-node-model)
  - [2.1 The runtime layer](#21-the-runtime-layer)
  - [2.2 The application layer](#22-the-application-layer)
  - [2.3 The execution layer](#23-the-execution-layer)
- [3. Invocation of the execution layer](#3-invocation-of-the-execution-layer)
  - [3.1 Lifecycle hooks](#31-lifecycle-hooks)
  - [3.2 The runtime prologue](#32-the-runtime-prologue)
  - [3.3 Argument vectors](#33-argument-vectors)
  - [3.4 Argument vector encoding](#34-argument-vector-encoding)
  - [3.5 Variable expansion](#35-variable-expansion)
- [4. Configuration](#4-configuration)
  - [4.1 Standardized process environment variables](#41-standardized-process-environment-variables)
- [5. Backend profiles](#5-backend-profiles)
- [6. Metadata](#6-metadata)
  - [6.1 Metadata keys and values](#61-metadata-keys-and-values)
  - [6.2 Runtime metadata](#62-runtime-metadata)
  - [6.3 Application metadata](#63-application-metadata)
  - [6.4 Execution metadata](#64-execution-metadata)
  - [6.5 SIL Kit participant metadata](#65-sil-kit-participant-metadata)
  - [6.6 Service description metadata](#66-service-description-metadata)
  - [6.7 Execution layer assembly](#67-execution-layer-assembly)
  - [6.8 Platform descriptor](#68-platform-descriptor)
  - [6.9 Data directory metadata](#69-data-directory-metadata)
- [7. Conformance](#7-conformance)
- [Normative references](#normative-references)

## Requirements language

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in BCP 14 [RFC2119] [RFC8174] when, and only when, they appear in all capitals, as shown here.

## Terminology

### Terms

| Term | Definition |
| ---- | ---------- |
| **simulation node** (or **node**) | A single unit of a distributed simulation: one application layer bound to one runtime layer, packaged so that it can be distributed and invoked independently (execution layer). Referred to simply as a *node* where the context is unambiguous. |
| **layer** | One of the three logical parts that define a node: runtime, application, or execution (§2). "Layer" is a conceptual term and does not refer to the specific implementation. |
| **CSIL registry** (or **registry**) | A store that holds packaged layers and serves them by reference. The registry's concrete form is defined by the backend profile (§5). |
| **reference** | The identifier by which a layer is addressed in a registry. Each backend profile (§5) defines its own syntax for references. |
| **host** | A machine on which orchestration can execute a node. A host provides an orchestration backend and advertises the platform it can execute as a **host capability** (§6.8.2). How hosts are configured, selected and addressed is a deployment concern outside the scope of this specification. |
| **deployment** | The act of resolving a node's configuration (§4) and invoking its hooks (§3) on a host. |
| **carrier** | The concrete mechanism by which a backend profile stores a metadata key and its value. |

### Roles

This specification places its requirements on the following roles:

| Role | Definition |
| ---- | ---------- |
| **producer** | The party that authors a runtime layer or an application layer and publishes it to a registry. |
| **tooling** | Any implementation that reads, validates, assembles, deploys or invokes nodes packaged under this specification. |
| **assembling tool** | Tooling acting at assembly time: it composes an execution layer from one runtime layer and one application layer. |
| **orchestration** | Tooling acting at deployment time: it resolves a node's environment, invokes the node's hooks and runs the simulation. |
| **consumer** | Tooling acting at read time: it reads a packaged layer's metadata in order to inspect, validate, assemble or deploy it. Every assembling tool and every orchestration is also a consumer. |

The assembling tool and orchestration are tooling in a particular role.
A requirement written on tooling therefore binds every implementation that performs the act it describes, whichever role it acts in.

A requirement written about a runtime or an application layer binds that layer's producer.
A requirement written about an execution layer binds the assembling tool that produced it.

A backend profile (§5) MAY define further roles for the packaging and execution mechanisms it describes.

## 1. Scope

This specification defines the structure, metadata vocabulary, and conventions for packaging simulation nodes for use in distributed SIL (Software in the Loop) environments, orchestrated via SIL Kit [SILKIT].

This specification is backend-agnostic: it defines a common vocabulary and a three-layer conceptual model that applies regardless of how exactly simulation nodes are packaged and distributed.
Backend profiles (see §5) define how the vocabulary maps to concrete packaging and distribution formats such as OCI container images.

The purpose of this specification is **artifact interoperability**: a layer packaged by any conformant producer MUST be consumable by any conformant consumer of the same backend profile, without knowledge of the tool that produced it.

The following are explicitly **outside** the scope of this specification:

- **Authoring formats**: How a producer arrives at a packaged layer is a tool concern.
  Only the packaged artifact is normative.
- **Simulation composition and deployment topology**: How a set of nodes is selected, wired and assigned to hosts for a particular simulation is a deployment concern.
  This specification defines only what an individual node declares about itself, including what it requires from its deployment (§4) and what it offers to one (§6.5, §6.6).
- **User interfaces**: For example, tool UIs, command sets, and configuration file locations.
- **Enforcement strategy**: This specification defines which artifacts are valid.
  Whether a given implementation reports an invalid artifact as a warning or an error, and at which point in its workflow it checks, is an implementation choice, except where §7 states otherwise.

### 1.1 Versioning and compatibility

This specification is versioned as `MAJOR.MINOR.PATCH`.

- A **MAJOR** increment may change or remove existing requirements.
  Artifacts and implementations of different major versions are not guaranteed to be able to interoperate.
- A **MINOR** increment is backward compatible: it may add keys, hooks, service types or profiles, but MUST NOT change the meaning of an existing key or make a previously valid artifact invalid.
- A **PATCH** increment carries only editorial corrections or clarifications.

Backward compatibility extends to **assembly**: an assembling tool that implements an earlier minor version MUST be capable of combining a runtime layer and an application layer produced against later minor versions.

Every packaged layer MUST declare the version of this specification it was produced against, via `csil.spec.version` (§6.2, §6.3, §6.4).

A consumer MUST NOT reject a layer solely because the layer's declared `spec.version` has the same major version and a minor version greater than the version the consumer implements.
In that case the layer may carry keys the consumer does not recognize; §6.1.5 defines how they are handled.
A consumer MAY reject a layer whose declared major version differs from its own, and MUST NOT try to interpret the layer without informing the user about the version mismatch.

## 2. Simulation node model

A simulation node is composed of three logical layers:

| Layer | Content |
| ----- | ------- |
| **Runtime** | Reusable base (typically containing the OS, tool binaries, shared libraries, ...) required to run certain application artifacts |
| **Application** | Artifacts (.so/.dll, scripts, configuration, ...) that are processed by a tool packaged in a runtime |
| **Execution** | Deployable simulation node, composed of one runtime and one application |

### 2.1 The runtime layer

The runtime layer provides information about the operating system requirements, the tool-specific requirements and the tool itself.

A runtime is identified by the tool it provides.
Tool identifiers use reverse domain name notation to avoid collisions.

Runtimes MUST declare the tool they provide as metadata (see §6.2).
Runtimes MAY declare configuration-variable requirements and defaults as metadata (see §4 and §6.7).

### 2.2 The application layer

An application layer contains all model artifacts required to run the model within the desired runtime, e.g., compiled model binaries, configuration files.

An application layer SHOULD contain only model content.
It SHOULD NOT contain an operating system or runtime binaries: those belong to the runtime layer, and duplicating them in the application layer undermines the separation the three-layer model exists to provide.
This is a design guideline addressed to producers; it is not a property a consumer can decide, and a consumer MUST NOT reject an application layer on the basis of its content alone.

Application metadata MUST be provided as part of the application artifact and MUST include the fields defined in §6.3.
The SIL Kit participant and service metadata (§6.5, §6.6) is authored on the application layer; it is inherited by the execution layer during assembly.
An application artifact MUST carry this metadata when its model hosts SIL Kit participants, and MUST omit it when it does not (§6.5); tooling MUST validate any metadata that is present per §6.5 and §6.6.

### 2.3 The execution layer

Execution layers combine a runtime layer with an application layer into an executable unit.
The execution layer uses the runtime layer as its base, adds the application layer to it and makes executing the application within the runtime possible.

The executable invoked to run the simulation node is not a metadata concept.
The full argument vector is assembled at invocation time from the runtime layer's prologue and the effective argument vector of the hook being invoked (§3).
The execution layer declares neither an entry point nor a program: it carries the composed argument vectors produced when it was assembled (§6.7.3).

Because every execution layer is built on exactly one runtime layer, and every runtime layer provides a prologue (§3.2) and declares a `start-node` hook (§6.2), every execution layer is invocable.
Tooling MUST reject an execution layer whose composed `start-node` vector is empty.

Execution layers MUST declare the metadata defined in §6.4 and MUST carry the participant and service metadata defined in §6.5 and §6.6 whenever their application layer declares it; it is inherited from the application layer (§2.2).
Execution layers MUST also inherit runtime requirement metadata from their base runtime layer (see §6.7.1).

## 3. Invocation of the execution layer

The invocation of the execution layer MUST be self-contained and only depend on specified requirements (see §4).

A simulation node is invoked by executing an **argument vector** through its runtime's **prologue**.
The prologue is a runtime implementation detail (§3.2) and the argument vector is data composed of metadata (§3.3).

### 3.1 Lifecycle hooks

A node exposes its behavior as named **lifecycle hooks**.
Each hook is invoked as its own argument vector through the same prologue:

| Hook | Required | Description |
| ---- | -------- | ----------- |
| `preflight` | OPTIONAL | Verifies deployment preconditions. |
| `start-node` | REQUIRED | Prepares and starts the node (and optionally starts a simulation lifecycle). This is the node's default hook. |
| `run-simulation` | OPTIONAL | Runs a simulation lifecycle. If set, invoked once a new simulation lifecycle is requested. |
| `stop-simulation` | OPTIONAL | Stops a simulation lifecycle. If set, invoked once a simulation lifecycle end is requested. |
| `shutdown-node` | OPTIONAL | Shuts down the node. This is the terminal teardown of the node. |

A hook is **present** on a node when its composed argument vector (§3.3) is non-empty.
Absence is not an error except for `start-node`, which MUST be present.

This table is the complete set of hooks defined by this version of the specification.
A future minor version MAY add further hooks (§1.1); a consumer MUST ignore a `csil.hook.<hook>.argv.<N>` key whose `<hook>` it does not recognize, per §6.1.5.

The `start-node` and `shutdown-node` lifecycle hooks target the node lifecycle.
The node lifecycle can outlive several simulation lifecycles.
Simulation lifecycles are targeted by the `run-simulation` and `stop-simulation` hooks.

A hook is considered **failed** if it produced a non-zero exit code.

### 3.2 The runtime prologue

Every runtime layer MUST provide a **prologue**: a backend-native command that prepares the runtime environment.
For example, a prologue might source setup scripts, adjust `PATH`, or configure DNS servers.
After performing any desired environment setup, the prologue MUST handle the argument vector it is given.

The prologue is an implementation concern of the runtime layer.
It MUST NOT be expressed in metadata, and a layer above the runtime MUST NOT observe or override it.
How a runtime carries its prologue is defined by the backend profile (§5).
This confines environment preparation to the runtime layer internals.

The prologue receives the effective argument vector of a hook and MUST handle it appropriately.
In most use-cases this means ending the prologue by executing the remaining effective argument vector (e.g., `exec "$@"` in POSIX shells).

Every hook is invoked through the prologue, so every hook, not just `start-node`, observes the same prepared environment.
Tooling MUST invoke every hook through the prologue and MUST NOT bypass the prologue.
In particular, tooling MUST NOT replace the prologue in order to execute a hook.

### 3.3 Argument vectors

A hook's **effective argument vector** is composed of two contributions:

1. The **runtime contribution** (§6.2) declares how the runtime's tool is invoked for that hook: the program and the options it is given.
   This is the hook's *invocation contract*, authored by the party that owns the tool.
2. The **application contribution** (§6.3) declares the operands the model supplies to that contract.

The effective argument vector is the runtime contribution followed by the application contribution, in that order.

The effective argument vector is computed when an execution layer is assembled.
The argument vector is recorded as part of the execution layer (§6.7.3), so tooling can inspect a node's full invocation without resolving the node's layers or invoking the hook.

An application MAY contribute to a hook for which its runtime declares no contribution.
The application's contribution alone then becomes the effective vector for that hook.
The only normative requirement is that the composed `start-node` vector (§6.7.3) is non-empty; every other hook may end up empty, in which case it is simply absent.

### 3.4 Argument vector encoding

An argument vector is encoded as indexed metadata keys, one **complete argv element per key**:

```txt
csil.hook.<hook>.argv.<N>
```

`<hook>` is one of the hook names defined in §3.1.
`<N>` is an index forming a contiguous zero-based sequence as defined in §6.1.4.

A key's value is one argv element, verbatim.
Tooling MUST NOT split it on whitespace or on any other delimiter, and MUST NOT subject it to any shell processing: no word splitting, no globbing, no command substitution, no tilde expansion, and no quote removal.
An element MAY therefore contain spaces, quotes and shell metacharacters without escaping.

An argv element MAY be the empty string.
An empty element is a genuine argv element and MUST be passed through as one; it does not terminate the sequence and does not make the hook absent.
A hook is absent only when it has no `argv.0` key (§6.1.4).

### 3.5 Variable expansion

An argv element MAY reference a configuration variable of the node's configuration (§4) using `${NAME}`.

`NAME` MUST match the following grammar, written in Extended Backus-Naur Form (EBNF):

```txt
NAME  =  ( ALPHA | "_" ) , { ALPHA | DIGIT | "_" } ;
ALPHA =  "A" | ... | "Z" | "a" | ... | "z" ;
DIGIT =  "0" | ... | "9" ;
```

This is the portable configuration-variable name character set.
A `${...}` sequence whose content does not match this grammar is **not** a variable reference and MUST be left as literal text.
Only the exact `${NAME}` form is recognized; any other appearance of `$` (a bare `$NAME`, a lone `$`) is likewise left as literal text.
There is no escape sequence: an element that must contain the literal characters `${NAME}` where `NAME` matches the grammar above cannot be expressed, and a producer needing such a value MUST supply it through a variable instead.

Tooling expands every `${NAME}` reference before invoking a hook, against the node's fully resolved deployment environment (§4).
This is a plain, per-element substitution on an already-tokenized argv array, never a re-parse of shell source, so it carries none of a shell's word-splitting, globbing, or command-substitution hazards (§3.4):

- Expansion is **per element**: an element expands to exactly one argv element, whatever the value contains.
  A value containing spaces does not become several arguments.
- The result MUST NOT be rescanned; a `${...}` sequence produced by an expansion is a literal.
- Only variable references are expanded.
  Command substitution, arithmetic expansion and globbing are not performed.

Referencing `${NAME}` in an argv element is itself a declaration of a variable requirement.
Consequently:

- If a referenced variable is unset during deployment (and gained no default from any layer), tooling MUST fail deployment (§4), consistently with any other unsatisfied requirement.
- Because assembly always composes the vector before the deployment environment is known (§6.7.3), expansion itself cannot happen at assembly time; it happens later, when tooling actually invokes a hook.

Since the hook receives already-expanded arguments, its runtime prologue (§3.2) never needs to perform substitution itself.
It MAY still layer its own additional native expansion on top (e.g., by invoking a shell), but that is an independent, optional capability of the prologue, not something the spec's `${NAME}` syntax relies on.

Example:

```txt
csil.hook.start-node.argv.0=cooltool
csil.hook.start-node.argv.1=-c
csil.hook.start-node.argv.2=${DATA_FILE}
```

Tooling automatically expands element 2 to its resolved value before invoking the hook.
This is the supported way to make an argument vector vary per deployment; argument vectors themselves are not overridable at deployment time (§6.7.3).

## 4. Configuration

The configuration variables defined here become variables in the launched process environment; they are distinct from the host environment used to prepare a runtime.

Simulation nodes MUST be configurable at deployment time via these variables.
The configuration is split into variables that MUST be provided and variables that MAY be overridden:

| Key | Value | Description |
| --- | ----- | ----------- |
| `csil.env.requires.<N>` | `KEY` | Variable that MUST be provided. |
| `csil.env.default.<N>` | `KEY=VALUE` | Variable with a provided default (overridable). |

`<N>` forms a contiguous zero-based sequence as defined in §6.1.4.

`KEY` MUST match the `NAME` grammar of §3.5.
An `env.default` value is split at the **first** `=` character: everything before it is the variable name and everything after it is the value.
A value MAY therefore itself contain `=` characters, which are not further interpreted.
A value MAY be empty (`KEY=`), which declares the variable's default value to be the empty string.

Example:

```txt
csil.env.requires.0=EXAMPLEAPP_LICENSE_FILE
csil.env.default.0=USER=appuser
```

A variable MAY be listed in both `env.requires` and `env.default`.
This means it is a requirement that already carries a default value: the default supplies it unless deployment overrides it.
When an execution layer is assembled, any layer MAY provide a default value for a variable declared as required by any other layer.
In that case the variable has an `env.requires` entry and additionally an `env.default.<N>=KEY=VALUE` entry (see §6.7.1); it is thereby considered satisfied.
For composition rules for `env.requires` and `env.default` see §6.7.2.

At deployment time, orchestration MUST verify that every `env.requires` variable of the execution layer is satisfied either by a declared `env.default` or by a deployment-provided value, and MUST fail deployment otherwise.
When multiple layers provide a default, the precedence rules in §6.7.2 apply.

This is a requirement on **deployment**, not on inspection.
A consumer that reads an execution layer in isolation, without deployment configuration, MUST NOT treat an `env.requires` variable that has no `env.default` as making the layer invalid.
Such a consumer SHOULD report the unsatisfied variable, so that the deployment obligation is visible before deployment is attempted.

### 4.1 Standardized process environment variables

The following process environment variables are standardized by this specification.
Orchestration MAY provide them automatically, without any deployment-time configuration, whenever a node declares one as required (`env.requires`, §4).

| Variable | Description |
| -------- | ----------- |
| `SILKIT_REGISTRY_URI` | SIL Kit registry URI (e.g., `silkit://host:8501`). Tooling MUST set this to the address of the simulation's SIL Kit registry. Applies to every simulation node. |

Simulation nodes MUST read `SILKIT_REGISTRY_URI` and pass it to all SIL Kit participants.

When a `participant.<N>.configuration.path` is present (see §6.5), the participant configuration file is authoritative for that participant: a SIL Kit registry URI set in the file overrides whatever the node passes through the API, and the value passed through the API applies only where the file omits it.

Because the file wins, orchestration cannot direct such a participant to the simulation's SIL Kit registry by setting the process environment variable alone.
Orchestration MUST therefore, for every participant whose declared configuration file sets a SIL Kit registry URI, rewrite that entry to the simulation's SIL Kit registry URI (§6.5 governs how such a rewrite is performed), **and** MUST set `SILKIT_REGISTRY_URI` for the node regardless.
The two act together: the variable directs participants that take the value from the API, and the rewrite directs those whose file would otherwise override it.

Which node acts as the SIL Kit system controller for a given simulation, and which SIL Kit registry that simulation uses, are deployment decisions outside the scope of this specification (§1).
This specification defines only the standardized variables that orchestration MUST set once it has made those decisions.

Example:

```txt
csil.env.requires.0=SILKIT_REGISTRY_URI
```

## 5. Backend profiles

This specification defines the metadata vocabulary and conceptual model only.
How simulation nodes are packaged, distributed, and executed is defined by backend profile documents:

- **OCI Backend** [CSIL-OCI]: Packaging as OCI container images and artifacts, distributed via an OCI-compatible registry, executed by a container runtime.
- **Folder Backend** [CSIL-FOLDER]: Packaging as a directory tree on a local or shared file system (the folder registry), executed natively as host processes (local execution).

## 6. Metadata

This section defines the metadata vocabulary, the keys and their semantics, which is the same regardless of carrier.
Carrier-specific encoding rules are defined in the respective backend profile document (see §5).

### 6.1 Metadata keys and values

Metadata is a flat map of string keys to string values. §6.1.1–§6.1.5 define the map's general rules; §6.2 onwards define the individual keys.

#### 6.1.1 Metadata key prefix

Vendor-specific metadata MAY be added using reverse domain name notation (e.g., `com.example.csil.`).

The prefix `csil.` is reserved for metadata keys defined by this specification.

#### 6.1.2 Key syntax

Metadata keys are **case-sensitive** and MUST be compared byte for byte.
All keys defined by this specification are lowercase; a consumer MUST NOT match them case-insensitively, and MUST NOT normalize the case of keys it forwards.

A key consists of dot-separated segments.
Where a key template in this specification contains a placeholder the placeholder occupies exactly one segment, and its permitted values are defined where the template is introduced.
Index placeholders (`<N>`, `<i>`, `<j>`) are decimal integers as defined in §6.1.4.

#### 6.1.3 Value encoding

**Every metadata value is a UTF-8 string.**
This specification defines no other value type.
Where a value is described below as a boolean, an integer, a set or a pair, that describes the *lexical form* of the string, not a native type in the carrier.

A backend profile MUST carry values such that this string is preserved exactly: a value written by a producer MUST be read back byte for byte by a consumer.
A carrier whose native serialization would type-coerce a value MUST be constrained by its profile such that coercion cannot occur.

The following lexical forms are used:

| Form | Definition |
| ---- | ---------- |
| **string** | Any UTF-8 string. Leading and trailing whitespace is significant and MUST NOT be trimmed. The empty string is permitted unless a key's definition states otherwise; for the distinction between an empty and an absent value see §6.1.4. |
| **boolean** | Exactly `true` or `false`, lowercase. No other spelling is valid: `True`, `TRUE`, `yes`, `on`, `1` and `0` are **not** booleans and MUST be rejected. Where a boolean key is OPTIONAL, its absence means `false`; a key that is present MUST carry one of the two valid spellings. |
| **integer** | A non-empty sequence of ASCII digits `0`–`9`, optionally preceded by `-`. No leading `+`, no leading zeros (except the single digit `0`), no whitespace, no grouping separators, no exponent. |
| **set** | Zero or more elements separated by `,` (U+002C). Elements MUST NOT contain `,`, and there is no escape mechanism. Surrounding whitespace around an element is not significant and MUST be trimmed by the consumer; empty elements MUST be ignored. Element order is not significant. Whether a set is interpreted as alternatives or as a conjunction is defined by each key that uses this form; the two uses are distinguished in §6.3.1 and §6.8.1. |
| **pair** | `KEY=VALUE`, split at the **first** `=`. `KEY` MUST be non-empty; `VALUE` MAY be empty and MAY contain further `=` characters, which are not interpreted. A pair with no `=` is malformed. |

Values are **not** subject to any expansion, escaping or interpretation beyond what the key's own definition states.
In particular, the `${NAME}` expansion of §3.5 applies **only** to argv element values, and only at hook invocation time.

#### 6.1.4 Indexed key sequences

Several key families are indexed: `argv.<N>` (§3.4), `env.requires.<N>` and `env.default.<N>` (§4), `participant.<N>` (§6.5), `service.<i>` (§6.6), `label.<j>` (§6.6.6), the backend requirement families (§6.7), and `data.<N>` (§6.9).

For every such family:

- An index is a decimal integer in the **integer** form specified in §6.1.3, restricted to non-negative values, without leading zeros.
- Indices MUST form a **contiguous sequence starting at 0**.
  A producer MUST NOT emit a gap.
- Indices are ordered **numerically**, not lexically.
  Index `10` follows index `9`.
- A family is **absent** when no key with index `0` is present.
  An absent family is not an error unless the key's own definition makes it REQUIRED.
- A key whose index is present but whose value is the empty string is a **present entry with an empty value**, not an absent entry.
  It does not terminate the sequence.

A consumer that encounters a **gap**, i.e. an index `k > 0` present while some index less than `k` is absent, MUST reject the layer as malformed.
It MUST NOT silently truncate the sequence at the gap, and MUST NOT renumber it.
Truncating would change an argument vector's meaning, or silently drop a declared requirement, without any signal to the operator.

A consumer that encounters a malformed index (leading zeros, a sign, a non-integer segment) MUST likewise reject the layer.

#### 6.1.5 Unknown keys

A consumer MUST ignore any key under `csil.` that it does not recognize, and MUST NOT reject a layer solely because such a key is present.
Unrecognized keys arise legitimately when a layer was produced against a later minor version of this specification (§1.1).

Ignoring an unknown key means treating it as having no effect on the consumer's own behavior.
It does **not** mean discarding it: an assembling tool MUST preserve every unrecognized `csil.` key from the runtime layer and from the application layer onto the execution layer it produces, unchanged.
A key that an assembling tool does not understand may still be meaningful to the orchestration that later deploys the result, and dropping it would silently strip a declaration the producer made.

Preserving a key is not the same as copying each occurrence of it.
Where both source layers carry the same unrecognized key, or the same unrecognized indexed family, copying both occurrences is not possible: execution layer metadata is a single flat map (§6.1), so one key cannot hold two values, and two independently numbered occurrences of one family would collide.
How an assembling tool composes unrecognized keys, and unrecognized indexed families of keys, is defined in §6.7.4.

This rule applies to unrecognized keys.
A key that this specification **does** define, carrying a malformed value, is an error and MUST be rejected per §6.1.3 and §6.1.4.

### 6.2 Runtime metadata

| Key | Required | Description |
| --- | -------- | ----------- |
| `csil.spec.version` | REQUIRED | Version of this specification the layer was produced against (§1.1), in `MAJOR.MINOR.PATCH` form, e.g., `1.0.0`. |
| `csil.type` | REQUIRED | MUST be `runtime` |
| `csil.runtime.tool` | REQUIRED | Tool identifier (reverse domain notation, e.g., `com.example.cooltool`) |
| `csil.runtime.tool.version` | REQUIRED | Tool version (e.g., `Y-2026.03`) |
| `csil.hook.start-node.argv.<N>` | REQUIRED | Runtime contribution to the `start-node` vector (§3.3): the program and options that invoke the tool, by the common convention where element 0 names the program (see §3.2, the prologue is free to interpret it otherwise). |
| `csil.hook.preflight.argv.<N>` | OPTIONAL | Runtime contribution to the `preflight` vector (§3.3). Absent means the runtime declares no `preflight` hook. |
| `csil.hook.run-simulation.argv.<N>` | OPTIONAL | Runtime contribution to the `run-simulation` vector (§3.3). Absent means the runtime declares no `run-simulation` hook. |
| `csil.hook.stop-simulation.argv.<N>` | OPTIONAL | Runtime contribution to the `stop-simulation` vector (§3.3). Absent means the runtime declares no `stop-simulation` hook. |
| `csil.hook.shutdown-node.argv.<N>` | OPTIONAL | Runtime contribution to the `shutdown-node` vector (§3.3). Absent means the runtime declares no `shutdown-node` hook. |

A runtime MUST declare a `start-node` contribution, since it defines the inspectable invocation contract for the application layer.
A runtime MUST also provide a prologue (§3.2), which is carried natively by the backend and is deliberately absent from this table.

The runtime's contribution defines the invocation contract that applications built on it conform to.
A runtime that accepts model operands SHOULD document the order and meaning of the operands it expects after its own elements.

In addition, a runtime MUST declare its own platform via the platform descriptor keys (§6.8) under the prefix `csil.runtime.` (e.g., `csil.runtime.os`, `csil.runtime.arch`).

### 6.3 Application metadata

Application metadata describes the model and its runtime requirements.

| Key | Required | Description |
| --- | -------- | ----------- |
| `csil.spec.version` | REQUIRED | Version of this specification the layer was produced against (§1.1), in `MAJOR.MINOR.PATCH` form, e.g., `1.0.0`. |
| `csil.type` | REQUIRED | MUST be `application` |
| `csil.application.name` | REQUIRED | Model/application name |
| `csil.application.version` | REQUIRED | Version of the model/application content (see below) |
| `csil.application.runtime.tool` | REQUIRED | Required tool identifier (reverse domain notation) |
| `csil.application.runtime.tool.version` | OPTIONAL | Required tool version. In pinned mode a single value; in loose mode a **set** of acceptable values (§6.1.3). Omitted means any version is acceptable. |
| `csil.application.runtime-id` | OPTIONAL | Exact runtime identifier; its presence pins the runtime (see coupling modes below); format is backend-specific (see backend profile) |
| `csil.hook.<hook>.argv.<N>` | OPTIONAL | Application contribution to `<hook>`'s vector (§3.3): the model's operands, appended after the runtime's elements. |

`application.version` versions the **application content** and is independent of the runtime's `runtime.tool.version`, which versions the tool.
Together with `application.name` it identifies a particular revision of a model.
Its value is opaque to this specification: it is a string (§6.1.3), compared only for equality, and this specification defines no ordering over it.
Backend profiles MAY use it to derive a reference, which is why it is REQUIRED rather than OPTIONAL.

An application MAY contribute to a hook its runtime declares no contribution for (§3.3); the only normative requirement is that the composed `start-node` vector is non-empty.

In addition, an application declares the platform of the runtime it requires via the platform descriptor keys (§6.8) under the prefix `csil.application.runtime.` (e.g., `csil.application.runtime.os`, `csil.application.runtime.arch`).
Unlike a runtime's own platform, this descriptor expresses a *requirement* about another layer.

#### 6.3.1 Coupling modes

The application's runtime requirement is expressed in one of two mutually exclusive shapes, distinguished by the presence of `csil.application.runtime-id`:

- **Pinned.**
  `application.runtime-id` is present and holds the authoritative runtime identifier.
  The `application.runtime.*` platform keys record a single concrete value each (the resolved runtime's platform).
  Tooling SHOULD verify that this required platform is satisfied by the runtime's own platform per the matching rules in §6.8.1; `application.runtime-id` takes precedence over field-by-field matching.
  A pinned application is bound to its runtime and is not rebindable.
- **Loose.**
  `application.runtime-id` is absent.
  The `application.runtime.*` keys then express a *loose requirement* rather than a resolved platform: the set-valued keys (`application.runtime.tool.version`, `application.runtime.os`, `application.runtime.arch`, `application.runtime.variant`, `application.runtime.os.variant`) MAY carry a **set** (§6.1.3) of acceptable values (a single value is a one-element set), and any one of the listed values satisfies the requirement.
  The `os.variant` requirement is matched against a candidate runtime's own `os.variant` label, not against a host (§6.8.2).
  `application.runtime.tool` remains a single value.
  A concrete runtime is resolved per target when an execution layer is assembled, choosing any runtime whose own platform (§6.8) satisfies every set requirement.
  Because the application layer binds no concrete runtime, it is target-agnostic and MAY be rebound to a different runtime backend by resolving it anew against another registry/host.

**`os.features` is not a set of alternatives.**
It uses the same comma-separated lexical form (§6.1.3) but keeps its §6.8.1 **conjunctive** meaning in both coupling modes: every feature listed in `application.runtime.os.features` must be present in the candidate's features, not merely one of them.
For this key, the set form means "all of", and it is deliberately excluded from the list above.

In addition to the fields above, an application artifact whose model hosts SIL Kit participants MUST carry the participant and service metadata that describes them (§6.5, §6.6); it is inherited by the execution layer during assembly (§2.2).
An application whose model hosts no participants carries none.

### 6.4 Execution metadata

| Key | Required | Description |
| --- | -------- | ----------- |
| `csil.spec.version` | REQUIRED | Version of this specification the layer was produced against (§1.1), in `MAJOR.MINOR.PATCH` form, e.g., `1.0.0`. |
| `csil.type` | REQUIRED | MUST be `execute` |
| `csil.application.name` | REQUIRED | Inherited from the application layer (§6.3) |
| `csil.application.version` | REQUIRED | Inherited from the application layer (§6.3) |
| `csil.execute.application` | REQUIRED | Application layer reference used in assembly |
| `csil.execute.runtime` | REQUIRED | Runtime layer reference used in assembly |
| `csil.hook.start-node.argv.<N>` | REQUIRED | Composed effective `start-node` vector (§3.3, §6.7.3) |
| `csil.hook.preflight.argv.<N>` | OPTIONAL | Composed effective `preflight` vector (§3.3, §6.7.3) |
| `csil.hook.run-simulation.argv.<N>` | OPTIONAL | Composed effective `run-simulation` vector (§3.3, §6.7.3) |
| `csil.hook.stop-simulation.argv.<N>` | OPTIONAL | Composed effective `stop-simulation` vector (§3.3, §6.7.3) |
| `csil.hook.shutdown-node.argv.<N>` | OPTIONAL | Composed effective `shutdown-node` vector (§3.3, §6.7.3) |

The hook rows above cover every hook defined in §3.1.
An execution layer MUST carry the composed vector of every hook that composes to a non-empty vector, and MUST NOT carry a key for a hook that composes to an empty one.

An execution layer declares no entry point and no program: it is invoked by executing a hook's effective vector through its runtime's prologue (§3).

An execution layer MUST also declare its own platform via the platform descriptor keys (§6.8) under the prefix `csil.runtime.`, carrying the values of the runtime layer it was assembled from, and MUST inherit that runtime's execution requirements (§6.7.1).

When a `preflight` vector is present, tooling MUST execute it before `start-node`, through the same prologue and in the same environment as `start-node` (§3.2).
A failing preflight MUST prevent the node from starting.

### 6.5 SIL Kit participant metadata

Participant metadata is OPTIONAL at the node level.
It describes the SIL Kit service surface.

All participant properties use zero-indexed keys scoped under `participant.<N>.`, where `N` starts at 0:

| Key | Required | Description |
| --- | -------- | ----------- |
| `csil.sil-kit.participant.count` | REQUIRED (if the node hosts any SIL Kit participants) | Number of participants, **integer** (§6.1.3), >= 1 |
| `csil.sil-kit.participant.<N>.name` | REQUIRED (for each `N` below `count`) | Participant name, non-empty |
| `csil.sil-kit.participant.<N>.coordinated` | REQUIRED (for each `N` below `count`) | **boolean** (§6.1.3); `true` if lifecycle-coordinated |
| `csil.sil-kit.participant.<N>.synchronized` | REQUIRED (for each `N` below `count`) | **boolean** (§6.1.3); `true` if time-synchronized |
| `csil.sil-kit.participant.<N>.configuration.path` | OPTIONAL | Path to the SIL Kit participant configuration file. Declaring it asserts that the participant loads that file, which makes the participant's services rebindable at deployment time (see below). The file is authoritative for the participant, so orchestration MUST rewrite a SIL Kit registry URI set in it (see §4.1). |

When `participant.count` is present with value `C`, the keys `name`, `coordinated` and `synchronized` MUST be present for every index `0 <= N < C`, and participant keys with index `>= C` MUST NOT be present.
A consumer MUST reject a node that violates this (§6.1.4).

Each participant's services (see §6.6) are scoped under the same `participant.<N>.` prefix.

A participant configuration overrides the values a participant supplies programmatically, selecting each service by its canonical name (§6.6.5).
The path is therefore declared in metadata rather than kept private to the model: it is the point at which tooling MAY rewrite a participant's configuration to rebind its services for a particular simulation.
A participant that declares no `configuration.path` is not rebindable and connects solely on the bindings it was built with.

Tooling that rewrites this file MUST preserve every setting it does not deliberately change.
The rewritten file MUST express the same configuration as the original in every respect other than the entries the rewrite deliberately sets; a setting the rewriting tool does not itself model MUST survive with its value intact.

This is a requirement on content, not on bytes.
Tooling MAY re-serialize the whole document, in any serialization the participant's configuration loader accepts, and is therefore not required to preserve the original file's formatting, key order, or commentary.
Tooling MUST NOT change the declared path: the model already names it, typically on the participant's own command line, so the name is part of the contract even when the content beneath it is re-serialized.

A rewrite applies to the copy of the file the node executes from.
Tooling MUST NOT modify the authored file in the model's own content.

Example:

```txt
csil.sil-kit.participant.count=2
csil.sil-kit.participant.0.name=MySut
csil.sil-kit.participant.0.coordinated=true
csil.sil-kit.participant.0.synchronized=true
csil.sil-kit.participant.0.service.count=1
csil.sil-kit.participant.0.service.0.can.identifier=CAN0
csil.sil-kit.participant.0.service.0.can.network=CAN_Net
csil.sil-kit.participant.1.name=Helper
csil.sil-kit.participant.1.coordinated=true
csil.sil-kit.participant.1.synchronized=false
```

### 6.6 Service description metadata

Service description metadata declares the SIL Kit services (bus controllers, publishers, subscribers, RPC clients and servers) used by each participant.

This metadata serves two purposes:

1. It enables tooling to verify simulation compatibility before deployment.
2. It publishes the **canonical names** by which a participant's services can be addressed, so that a deployment can rebind them through a participant configuration (§6.5) without rebuilding the application layer.

Service metadata describes a model's services as packaged, not the wiring of one particular simulation: the binding fields record defaults that a deployment MAY override (§6.6.5).

Service metadata is OPTIONAL, on the same terms as the participant metadata: it is declared for the services a participant does declare, and its absence asserts nothing about services a model creates dynamically at runtime.

Service metadata applies to all backends, using the same key patterns.

#### 6.6.1 Scoping

Service keys are scoped per participant using the same indexing scheme as §6.5:

```txt
csil.sil-kit.participant.<N>.service.<i>.<type>.<field>
```

#### 6.6.2 Service count

A service count key declares the total number of services for participant `N`:

| Key pattern | Required | Description |
| ----------- | -------- | ----------- |
| `...participant.<N>.service.count` | REQUIRED (if any services) | Total service entries for participant N (integer >= 1) |

#### 6.6.3 Service entry format

Each service is described by a zero-indexed entry `<i>` (where `0 <= i < count`).
Every entry MUST contain exactly one service type prefix and its associated fields.

The general pattern is:

```txt
...<i>.<type>.<field>
```

#### 6.6.4 Service types

| Type         | Description         | Required Fields          |
| ------------ | ------------------- | ------------------------ |
| `can`        | CAN bus controller  | `identifier`, `network`  |
| `ethernet`   | Ethernet controller | `identifier`, `network`  |
| `flexray`    | FlexRay controller  | `identifier`, `network`  |
| `lin`        | LIN controller      | `identifier`, `network`  |
| `pub`        | Data publisher      | `identifier`, `topic`    |
| `sub`        | Data subscriber     | `identifier`, `topic`    |
| `rpc-client` | RPC client          | `identifier`, `function` |
| `rpc-server` | RPC server          | `identifier`, `function` |

#### 6.6.5 Field definitions

| Field | Applies to | Required | Description |
| ----- | ---------- | -------- | ----------- |
| `identifier` | All types | REQUIRED | The service's **canonical name**: the name the participant creates the service with, and the key an injected participant configuration selects it by (§6.5). |
| `network` | `can`, `ethernet`, `flexray`, `lin` | REQUIRED | The network/cluster name the controller is attached to. |
| `topic` | `pub`, `sub` | REQUIRED | The topic name used for data exchange. |
| `function` | `rpc-client`, `rpc-server` | REQUIRED | The remote function name used for the call. |
| `label.<j>.*` | `pub`, `sub`, `rpc-client`, `rpc-server` | OPTIONAL | Matching labels (see §6.6.6). |
| `media-type` | `pub`, `sub` | OPTIONAL | The media type of the exchanged data. Informational: unlike the fields above it is not settable through a participant configuration, so it constrains matching but cannot be remapped. |

`identifier` selects a service; `network`, `topic` and `function` bind it.
The binding fields record the service's **default** binding as packaged, the binding a deployment establishes can differ, because a participant configuration overrides them (§6.5).
Tooling MUST NOT treat a binding field as the authoritative runtime binding without accounting for the configuration in effect.

#### 6.6.6 Labels

`pub`, `sub`, `rpc-client` and `rpc-server` services are matched by their binding field **and** by labels.
A service that declares labels MUST describe them, otherwise two services agreeing on `topic` or `function` cannot be determined to connect:

```txt
...<i>.<type>.label.<j>.key
...<i>.<type>.label.<j>.value
...<i>.<type>.label.<j>.kind
```

| Field   | Required | Description                                       |
| ------- | -------- | ------------------------------------------------- |
| `key`   | REQUIRED | Label key                                         |
| `value` | REQUIRED | Label value                                       |
| `kind`  | OPTIONAL | `mandatory` or `optional`; defaults to `optional` |

Label indices `<j>` form a contiguous zero-based sequence as defined in §6.1.4.
No label count key is defined: a service with no `label.0.key` declares no labels.

#### 6.6.7 Constraints

- Service indices `<i>` form a contiguous zero-based sequence as defined in §6.1.4, and MUST satisfy `0 <= i < count` where `count` is the participant's `service.count`.
- Each index MUST declare exactly one service type (no mixing of types within one index).
  A consumer MUST reject an entry declaring fields of two types.
- This specification sets no upper bound on the number of service metadata entries.
  Tooling MUST NOT reject a node solely because of the size of its service metadata; a complex participant can exceed 10,000 entries.
  A backend profile whose carrier imposes a size limit MUST document that limit.

### 6.7 Execution layer assembly

Assembly reduces two source layers to one.
Two rules govern every composition in this section:

- a **named value** composes by **override**: where both layers declare it, the later layer in the precedence order of §6.7.2 wins;
- an **ordered sequence** composes by **concatenation**: the runtime layer's entries come first, the application layer's entries follow, and the result is recorded as one contiguous zero-based sequence (§6.1.4).

§6.7.2 and §6.7.3 apply these rules to the keys this specification defines; §6.7.4 applies them to keys the assembling tool does not recognize.

Runtimes MAY declare execution requirements as metadata using keys under the prefix `csil.runtime.requires.*`.
This specification defines no requirement type itself: each backend profile (§5) defines the requirement types meaningful for its execution mechanism.

Requirement keys are opaque to any consumer that does not implement the backend that defines them.
Such a consumer MUST forward them unchanged (§6.1.5) rather than interpret or drop them.

#### 6.7.1 Inheritance

Runtimes MAY declare execution requirements as metadata using keys under the prefix `csil.runtime.requires.`.
The requirement types are defined by the backend profiles (§5).

When assembling an execution layer from a runtime and an application layer, the assembling tool MUST preserve every key matching the prefix `csil.runtime.requires.*` in the execution layer metadata.
This allows tooling to inspect execution layer metadata directly without needing access to the original runtime layer metadata.

The assembling tool composes environment requirements (`env.requires.*`) and defaults (`env.default.*`) onto the execution layer.
If a key is required and has a default, it appears in both `env.requires.*` and `env.default.*`.
If multiple layers provide a default for the same key, the assembling tool MUST apply the conflict resolution rules of §6.7.2.

A runtime declares the environment its prologue (§3.2) and its argument vector contributions (§6.2) need, and those requirements and defaults are inherited by the execution layer.
When any layer's argv contribution references `${NAME}` (§3.5), the assembling tool MUST automatically add every such variable as an additional `env.requires` entry on the execution layer, if it is not already declared.
Referencing a variable in argv is itself a declaration of the requirement.

The assembling tool MUST also carry onto the execution layer:

- the application layer's `application.name` and `application.version` (§6.4);
- the runtime layer's platform descriptor (§6.8), under the `csil.runtime.` prefix;
- the participant and service metadata (§6.5, §6.6) declared by the application layer, unchanged;
- every unrecognized `csil.` key from either source layer (§6.1.5), composed per §6.7.4 where both layers carry it.

The execution layer's `csil.spec.version` is decided by the **assembling tool**, based on its implementation of the compatibility contract.
An assembling tool MUST NOT produce an execution layer declaring a version it does not itself implement.

#### 6.7.2 Conflict resolution

Environment default `env.default` values progressively supersede values with the same key in the following order:

1. Runtime layer values
2. Application layer values
3. Execution layer values
4. Orchestration values

The assembling tool MUST propagate the highest order value per key through inheritance.

Orchestration MAY override any `env.default` value, and MUST provide every `env.requires` variable that has no `env.default`.

#### 6.7.3 Argument vector composition

Argument vectors compose by **concatenation**, not by override.
For **each hook defined in §3.1**, the assembling tool MUST produce the effective vector (§3.3) by appending the application layer's contribution to the runtime layer's contribution, and MUST record it on the execution layer as a single contiguous, zero-based sequence of `csil.hook.<hook>.argv.<N>` keys.

Where both contributions are absent the composed vector is empty; the hook is then absent (§3.1) and the assembling tool MUST NOT record any key for it.
This is how the OPTIONAL hook rows of §6.4 come to be present or absent.

The assembling tool MUST apply this composition to every hook it recognizes, including hooks for which only one of the two layers contributes.
A hook name it does not recognize is handled as an unknown key (§6.1.5) and composed structurally per §6.7.4, which for an `argv` family yields the same concatenation this subsection requires.

The conflict resolution order of §6.7.2 does not apply.
A vector is ordered data, not a named value, so a later layer neither replaces nor merges with an earlier one; it only extends it.
Consequently, an index on the execution layer does not correspond to the same index on the layer that contributed it.

The assembling tool MUST preserve every element verbatim and MUST NOT expand `${NAME}` references (§3.5): the deployment environment is not yet known at assembly time, so expansion happens later, when tooling actually invokes a hook against the node's resolved environment (§3.5); this keeps an assembled execution layer deployment-independent.

#### 6.7.4 Composition of unrecognized keys

An assembling tool MUST forward unrecognized `csil.` keys onto the execution layer (§6.1.5).
Where the same key or the same indexed family is present on **both** source layers, the tool MUST compose the two occurrences into one, and MUST do so **structurally**: using only the key syntax of §6.1.2 and the index rules of §6.1.4, without interpreting the key's meaning.

For the purposes of this subsection:

- an **index segment** is a key segment that is a valid index per §6.1.4;
- the **family root** of a key containing at least one index segment is the sequence of segments preceding its *first* index segment;
- the **entry suffix** is the sequence of segments following that first index segment; it MAY be empty, and MAY itself contain further index segments, which are not interpreted here.

**Keys without an index segment.**
The key is forwarded once.
Where both source layers declare it, the assembling tool MUST forward the application layer's value and MUST NOT forward the runtime layer's, per the precedence order of §6.7.2.

**Indexed families.**
Unrecognized keys sharing a family root form one family.
Within a source layer, the keys sharing a value of the first index segment form one **entry**, whose content is the set of (entry suffix, value) pairs it carries.

The composed family is the runtime layer's entries in numeric index order, followed by the application layer's entries in numeric index order.
The assembling tool MUST renumber the composed entries as a contiguous zero-based sequence in that order, and MUST reproduce every entry suffix and every value verbatim.

Where only one source layer declares a family, renumbering is the identity, because a conformant producer already emits a contiguous zero-based sequence (§6.1.4, §7.1); the family is then forwarded unchanged.

The assembling tool MUST NOT deduplicate entries, MUST NOT reorder them, and MUST NOT merge two entries because their contents are equal.
It cannot know whether the family's semantics make a repeated entry redundant.

Composing a forwarded key does not make the assembling tool an implementation of the version that defined it.
The execution layer's `csil.spec.version` remains the version the assembling tool itself implements (§6.7.1).

### 6.8 Platform descriptor

A platform descriptor identifies an execution platform.
It appears in two roles: a layer's **own platform** (runtime and execution layers, prefix `csil.runtime.`) and a **runtime requirement** (application layers, prefix `csil.application.runtime.`).
A field key is the role prefix followed by the suffix below.

| Suffix | Required | Description |
| ------ | -------- | ----------- |
| `os` | REQUIRED | OS/kernel family. MUST be an `os` value defined by [OCI-IMAGE-INDEX]. |
| `arch` | REQUIRED | CPU architecture. MUST be an `architecture` value defined by [OCI-IMAGE-INDEX]. |
| `variant` | OPTIONAL | CPU variant. MUST be a `variant` value defined by [OCI-IMAGE-INDEX]. |
| `os.features` | OPTIONAL | Required OS features, a **set** (§6.1.3) matched conjunctively (§6.8.1). Every feature MUST be an `os.features` value defined by [OCI-IMAGE-INDEX]. |
| `os.variant` | OPTIONAL | Userland variant. It MUST be a non-empty, case-insensitive identifier containing only ASCII letters, digits, `.`, `-` or `_` (e.g., `ubuntu2404`). |

In the **requirement** role on an application layer in loose coupling mode (§6.3.1), `os`, `arch`, `variant` and `os.variant` carry a **set** of acceptable values matched as alternatives.
`os.features` is the exception and is always conjunctive; see §6.3.1.

Consumers MUST reject a platform descriptor whose `os`, `arch`, `variant` or `os.features` value is not defined by [OCI-IMAGE-INDEX].
The `os.variant` value space is defined above and is not an OCI platform field.

#### 6.8.1 Matching

Tooling MUST apply the following matching rules whenever it matches a platform requirement (`R`) against a platform or host capability (`P`).

A field constrains the matching between `R` and `P` only when **both** `R` and `P` specify that field.
An absent field, where allowed, is a wildcard on either side; an absent field in `R` imposes no requirement, and an absent field in `P` means the capability supports any required value.

Concretely, `R` is satisfied by `P` if and only if, for every field specified in **both**:

- `os`, `arch`, `variant`: equal to `P`'s value (case-insensitive)
- `os.variant`: equal to `P`'s value (case-insensitive)
- `os.features`: when `P` announces features, every feature in `R` is present in `P`

#### 6.8.2 Host matching

When the platform `P` is a **host capability** (the platform a host's backend reports it can execute), the userland variant (`os.variant`) MAY be **excluded** from the match: then only the kernel-level fields (`os`, `arch`, `variant`, `os.features`) constrain host selection.
A host MAY advertise only the kernel platform it provides.

#### 6.8.3 Runtime matching

During runtime selection, a loose requirement's `os.variant` (§6.3.1) is matched against the candidate runtime's own `os.variant` label using the rule of §6.8.1.
The runtime that a host provides therefore determines the userland, and the host's role is limited to providing a compatible kernel/architecture.

### 6.9 Data directory metadata

| Key                  | Required | Description                                |
| -------------------- | -------- | ------------------------------------------ |
| `csil.data.<N>.path` | OPTIONAL | A data directory announced to the tooling. |

Indices MUST be contiguous starting from 0 and MUST be ordered numerically.
Tooling MUST allow declaring no data directory.

#### 6.9.1 Persistence guarantee

Tooling MUST provision the storage backing a declared data directory before the node starts, and MUST preserve its content for at least the whole node lifecycle, from before `start-node` until after `shutdown-node`.

How a backend provides that storage is defined by its backend profile (§5).

#### 6.9.2 Composition

An execution layer's effective list of data directories are the runtime layer's declarations followed by the application layer's declarations.

An application MAY declare a directory that its runtime already declares.
Both declarations then refer to the same directory, which MUST be provisioned only once.

#### 6.9.3 Path form

The form of a declared data directory's path is defined by the backend profile (§5), which MUST resolve the path the same way the node's own execution environment does.
A declared directory's path MUST NOT contain a `..` component in any profile.

## 7. Conformance

An implementation conforms to this specification with respect to one or more **backend profiles** (§5).
Conformance is always stated as "conformant to this specification under the *X* profile"; there is no profile-independent conformance, because a layer cannot be packaged without a carrier.

An implementation MUST document which profiles it implements, and which version of this specification it implements (§1.1).

### 7.1 Conformant producer

A conformant producer:

- MUST emit, for every layer it publishes, all keys marked REQUIRED for that layer's type (§6.2, §6.3, §6.4), with values in the lexical forms of §6.1.3;
- MUST emit `csil.spec.version` on every layer;
- MUST emit indexed key families as contiguous zero-based sequences (§6.1.4);
- MUST NOT author a key under `csil.` not defined in the specification version the producer declares in `csil.spec.version` (keys forwarded under §6.1.5 are exempt);
- MUST encode those keys and values in the carrier the profile defines.

### 7.2 Conformant consumer

A conformant consumer:

- MUST read every REQUIRED key of the layer types it handles, from the carrier the profile defines;
- MUST reject a layer that is missing a REQUIRED key, that carries a malformed value for a key this specification defines (§6.1.3), or that violates the index rules of §6.1.4;
- MUST ignore, and MUST NOT reject a layer because of, any key under `csil.` that it does not recognize (§6.1.5);
- MUST NOT reject a layer solely because of a naming convention, because of the size of its metadata, or because an `env.requires` variable has no default (§4);
- MUST NOT reject a layer solely because the layers `spec.version` has the same major version as its own and a greater minor version (§1.1).

**Rejecting a valid layer is a conformance failure.**
A consumer that imposes requirements this specification does not state is not conformant, because artifacts that other conformant producers legitimately emit will fail against it.

### 7.3 Conformant assembling tool

A conformant assembling tool is a conformant consumer of runtime and application layers and a conformant producer of execution layers.
In addition, it:

- MUST compose argument vectors by concatenation, per §6.7.3, and MUST NOT expand `${NAME}` references while doing so;
- MUST apply the environment precedence rules of §6.7.2;
- MUST preserve runtime requirement keys (§6.7.1) and unrecognized `csil.` keys (§6.1.5) onto the execution layer;
- MUST compose an unrecognized key declared by both source layers structurally, per §6.7.4, and MUST NOT emit a duplicated key or a non-contiguous index sequence as a result of forwarding;
- MUST reject an assembly whose composed `start-node` vector would be empty (§2.3).

### 7.4 Conformant orchestration

A conformant orchestration is a conformant consumer of execution layers.
In addition, it:

- MUST invoke every hook through the runtime's prologue, and MUST NOT bypass or replace it (§3.2);
- MUST expand `${NAME}` references against the node's resolved environment before invoking a hook, per §3.5;
- MUST fail deployment when an `env.requires` variable is satisfied neither by a default nor by deployment-provided configuration (§4);
- MUST execute a present `preflight` vector before `start-node`, and MUST NOT start the node if the preflight hook fails (§6.4);
- MUST set the standardized process environment variables it provides per §4.1.

### 7.5 Interoperability

The practical test of conformance is exchange: a layer published by any conformant producer under a profile MUST be consumable by any conformant consumer of that profile, with no knowledge of the producing implementation.

## Normative references

- **[RFC2119]** Bradner, S., "Key words for use in RFCs to Indicate Requirement Levels", BCP 14, RFC 2119, DOI 10.17487/RFC2119, March 1997, <https://www.rfc-editor.org/info/rfc2119>.
- **[RFC8174]** Leiba, B., "Ambiguity of Uppercase vs Lowercase in RFC 2119 Key Words", BCP 14, RFC 8174, DOI 10.17487/RFC8174, May 2017, <https://www.rfc-editor.org/info/rfc8174>.
- **[SILKIT]** *The SIL Kit Project*, <https://github.com/vectorgrp/sil-kit>, documentation: <https://vectorgrp.github.io/sil-kit-docs/index.html>.
- **[CSIL-OCI]** *CSIL Node Packaging Specification: OCI Backend Profile*, version 1.0.0 ([OCI](OCI.md)).
- **[CSIL-FOLDER]** *CSIL Node Packaging Specification: Folder Backend Profile*, version 1.0.0 ([FOLDER](FOLDER.md)).
- **[OCI-IMAGE-INDEX]** *OCI Image Index Specification*, version 1.1.0, Open Container Initiative, <https://github.com/opencontainers/image-spec/blob/v1.1.0/image-index.md>.
