# CSIL: OCI Backend Profile

| Version   | 1.0.0      |
| --------- | ---------- |
| Published | 2026-09-30 |

## Contents

- [Scope](#scope)
- [Requirements language](#requirements-language)
- [Terminology](#terminology)
- [1. Metadata carriers](#1-metadata-carriers)
  - [1.1 Platform descriptor encoding](#11-platform-descriptor-encoding)
  - [1.2 Value encoding](#12-value-encoding)
  - [1.3 Metadata size limits](#13-metadata-size-limits)
- [2. Runtime layer](#2-runtime-layer)
- [3. Application layer](#3-application-layer)
  - [3.1 Manifest structure](#31-manifest-structure)
  - [3.2 Config descriptor](#32-config-descriptor)
  - [3.3 Layers](#33-layers)
- [4. Execution layer](#4-execution-layer)
  - [4.1 Prologue and hook invocation](#41-prologue-and-hook-invocation)
- [5. OCI-Specific execution requirements](#5-oci-specific-execution-requirements)
  - [5.1 Mounts](#51-mounts)
  - [5.2 Data directories](#52-data-directories)
- [6. Naming conventions](#6-naming-conventions)
- [7. Reference resolution](#7-reference-resolution)
- [Normative references](#normative-references)

## Scope

This document defines the OCI backend profile for the CSIL Node Packaging Specification [CSIL].
It specifies how the vocabulary defined in that specification is carried by OCI container images and OCI artifacts distributed via an OCI-compatible registry, and adds OCI-specific execution requirements.

## Requirements language

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in BCP 14 [RFC2119] [RFC8174] when, and only when, they appear in all capitals, as shown here.

## Terminology

The roles defined in [CSIL] *Terminology* apply unchanged.

## 1. Metadata carriers

The OCI backend uses two distinct carriers for the metadata vocabulary defined in [CSIL] §6:

| Carrier | Identified by | Used for |
| ------- | ------------- | -------- |
| OCI image config labels | image config media type `application/vnd.oci.image.config.v1+json`, or `application/vnd.docker.container.image.v1+json` | Runtime ([CSIL] §6.2), execution ([CSIL] §6.4), SIL Kit metadata ([CSIL] §6.5, [CSIL] §6.6) |
| OCI artifact manifest annotations | manifest media type `application/vnd.oci.image.manifest.v1+json` with `artifactType` `application/vnd.csil.application` (§3) | Application ([CSIL] §6.3), SIL Kit metadata ([CSIL] §6.5, [CSIL] §6.6) |

Both image config media types MUST be accepted by a consumer.
The OCI-native media type is the one a producer SHOULD emit; the Docker media type is widespread in existing registries and toolchains and is therefore accepted on equal terms.

Image config labels are the `Labels` map of the image configuration's `config` object, as defined by [OCI-IMAGE].
Manifest annotations are the `annotations` map of the manifest itself, not of any descriptor it contains and not of an index referencing it.

The `csil.*` key vocabulary is used unchanged in both carriers.

### 1.1 Platform descriptor encoding

The platform descriptor ([CSIL] §6.8) is carried entirely by the `csil.*` metadata vocabulary, so that a runtime, execution, or application image is fully self-describing per the specification when inspected with any OCI-aware tool, without this backend or any other tooling having to augment it.
Tooling MUST NOT source the [CSIL] §6 metadata from the OCI image config platform.

Because a runnable OCI image also carries a native platform in its **image config** (`os`, `architecture`, `variant`, `os.features`), these labels necessarily duplicate the config fields.
This duplication is intentional: the specification vocabulary is the single normative source, and the image config is the container engine's own concern.
A producer MUST set the labels, and their values MUST agree with the image config platform.
Tooling reads the descriptor from the labels; it MAY additionally cross-check them against the image config and reject an image whose labels and config disagree.

### 1.2 Value encoding

Both carriers are JSON string maps, so [CSIL] §6.1.3's requirement that every metadata value is a UTF-8 string is met natively: a value is carried as a JSON string and read back byte for byte.
No type coercion is possible or permitted.

A producer MUST NOT encode a value as a JSON number, boolean, null, array or object.
A boolean is the JSON string `"true"` or `"false"`, never the JSON literal `true` or `false`.
An integer is a JSON string of digits, never a JSON number.
A consumer encountering a non-string JSON value under a `csil.` key MUST reject the layer.

An empty value is the empty JSON string `""`.
It denotes a present key with an empty value, which [CSIL] §6.1.4 distinguishes from an absent key.
A producer MUST NOT express "absent" by emitting an empty string, and a consumer MUST NOT treat an empty string as absence.

### 1.3 Metadata size limits

[CSIL] §6.6.7 sets no upper bound on service metadata, and notes that a complex participant can exceed 10,000 entries.
In this profile all such metadata is carried inside the image config or the manifest, both of which are blobs an OCI registry stores and serves as a unit.
Registries commonly impose a maximum manifest size and an image config is subject to the registry's blob limits.

Producers SHOULD therefore be aware that a sufficiently large service metadata set can produce an artifact that a conformant OCI registry legitimately refuses to accept.
This is a limit of the carrier.

## 2. Runtime layer

An OCI runtime layer is implemented as a container image that carries runtime metadata ([CSIL] §6.2) as image labels, provides the runtime prologue as its `Entrypoint` (§4.1), and optionally declares OCI-specific execution requirements (§5).
Its own platform descriptor ([CSIL] §6.8) is carried as image labels per §1.1 (`csil.runtime.os`, `...runtime.arch`, `...runtime.variant`, `...runtime.os.features`, `...runtime.os.variant`).

## 3. Application layer

An OCI application layer is implemented as an **OCI artifact**: an image manifest that carries content but is not runnable.
It is stored in and distributed by any OCI-compatible registry, using any client conforming to [OCI-DIST].

### 3.1 Manifest structure

The artifact is an OCI image manifest (`application/vnd.oci.image.manifest.v1+json`) constructed as follows:

| Field | Requirement |
| ----- | ----------- |
| `mediaType` | MUST be `application/vnd.oci.image.manifest.v1+json` |
| `artifactType` | MUST be `application/vnd.csil.application` |
| `config` | MUST be the empty descriptor (§3.2) |
| `layers` | MUST contain at least one descriptor carrying the model content (§3.3) |
| `annotations` | MUST carry the metadata defined in [CSIL] |

A consumer identifies a CSIL application layer by `artifactType`.
It MUST NOT rely on the repository or tag name to do so (§6).

### 3.2 Config descriptor

An application layer has no runnable configuration, so its `config` descriptor MUST be the empty descriptor defined by [OCI-IMAGE].

This is the OCI-native way of expressing "this manifest is not an image", and it is what makes [CSIL] §2.2's requirement that an application layer declare no execution information decidable in this profile: an application layer has no image config, therefore no `Entrypoint` and no `Cmd`, and a consumer can verify this by inspecting the descriptor.
A consumer MUST reject an artifact declaring `artifactType` `application/vnd.csil.application` whose `config` is a runnable image config.

### 3.3 Layers

Model content is carried in the manifest's `layers`.
Each descriptor's `mediaType` MUST be one of:

| Media type | Content |
| ---------- | ------- |
| `application/vnd.oci.image.layer.v1.tar` | An uncompressed tar archive of the model content |
| `application/vnd.oci.image.layer.v1.tar+gzip` | A gzip compressed tar archive of the model content |

A producer SHOULD use a single layer containing the complete model content, and SHOULD prefer the compressed form.

Paths within the archive are relative to the root of the model content, and MUST NOT begin with `/` or contain `..` components.
They are the paths the model sees at runtime, relative to the directory the application content is materialized into in the execution image (§4).
A `participant.<N>.configuration.path` ([CSIL] §6.5) is resolved against that same root, so a configuration file stored in the archive as `SilKitConfig.yaml` is declared as `SilKitConfig.yaml`.

A consumer MUST preserve archive entry paths, permissions and the executable bit when materializing content into an execution image.
Model content routinely includes executables that the runtime's argument vector names.

## 4. Execution layer

An OCI execution layer is implemented as a container image that combines a runtime image and an application artifact.
It uses the runtime image as its base and adds the application files.

### 4.1 Prologue and hook invocation

The runtime prologue ([CSIL] §3.2) is carried by the image's `Entrypoint`.
It is baked into the runtime image and inherited by the execution image through the base image, so it never appears in metadata.
A runtime image MUST set an `Entrypoint` that prepares the environment and defines a contract for its argument vector.

A hook is invoked by supplying its effective vector as the container's arguments, which the `Entrypoint` then executes.

An execution image MUST set `Cmd` to its composed `start-node` vector, one array element per argv element.
Tooling MUST invoke non-`start-node` hooks by overriding the arguments only.

Tooling MUST NOT override the image's `Entrypoint` (e.g., with Docker's `--entrypoint`) to invoke a hook.
Doing so replaces the prologue, so the hook runs without the prepared environment.
Only the container's arguments (`Cmd`) MAY be set.

#### 4.1.1 Variable expansion and `Cmd`

`Cmd` is passed to the container verbatim; the container engine performs no variable expansion on it.
An effective vector containing `${NAME}` references ([CSIL] §3.5) is therefore recorded, unexpanded, in both the image's labels and its default `Cmd`.

## 5. OCI-Specific execution requirements

The OCI backend additionally supports the following container-specific requirement keys.

**Key prefix:** `csil.runtime.requires`

### 5.1 Mounts

OCI runtime images that require file system mounts declare them as indexed entries:

| Key                                         | Description       |
| ------------------------------------------- | ----------------- |
| `csil.runtime.requires.mount.<N>.<segment>` | Mount description |

`<N>` forms a contiguous zero-based sequence as defined in [CSIL] §6.1.4.

The `<segment>` keys are provided as following:

| Segment       | Description                                     |
| ------------- | ----------------------------------------------- |
| `type`        | Mount type (see below).                         |
| `destination` | In-container mount path.                        |
| `options`     | Comma-separated mount options (type-dependent). |

Orchestration MUST support the `tmpfs` mount type, translating each `tmpfs` entry to the corresponding container engine flag (e.g., a Docker `--tmpfs` mount).

Example:

```txt
csil.runtime.requires.mount.0.type=tmpfs
csil.runtime.requires.mount.0.destination=/dev/shm
csil.runtime.requires.mount.0.options=rw,nosuid,nodev,exec,size=256m
```

### 5.2 Data directories

A node's declared data directories ([CSIL] §6.9) are backed by **volumes**.

For each data directory `csil.data.<N>.path`, tooling MUST mount a volume into the node's container at that path before the container is started.
The volume MUST outlive that container.

A data directory MUST be an absolute path in the container's own OS form.

## 6. Naming conventions

Tooling MUST NOT reject an image or artifact solely because its name does not follow a specific convention, and MUST base all validation on metadata (§1.1, [CSIL] §6).

## 7. Reference resolution

A reference under this profile takes one of the forms:

```txt
<registry>/<repository>:<tag>
<registry>/<repository>@<digest>
<registry>/<repository>
```

A digest-qualified reference identifies exactly one immutable manifest and is the form producers SHOULD use wherever reproducibility matters.

A tag-qualified reference identifies whatever manifest the tag currently points to.
Tags are mutable: the content behind a tag can change without the reference changing.
Consumers that require reproducibility MUST resolve a tag to a digest and record the digest.

A reference with **no tag and no digest** MUST be resolved as the tag `latest`, per established OCI registry convention.
A consumer MUST NOT invent a different default.

## Normative references

- **[RFC2119]** Bradner, S., "Key words for use in RFCs to Indicate Requirement Levels", BCP 14, RFC 2119, DOI 10.17487/RFC2119, March 1997, <https://www.rfc-editor.org/info/rfc2119>.
- **[RFC8174]** Leiba, B., "Ambiguity of Uppercase vs Lowercase in RFC 2119 Key Words", BCP 14, RFC 8174, DOI 10.17487/RFC8174, May 2017, <https://www.rfc-editor.org/info/rfc8174>.
- **[CSIL]** *CSIL Node Packaging Specification*, version 1.0.0 ([SPEC](SPEC.md)).
- **[OCI-IMAGE]** *OCI Image Format Specification*, version 1.1.0, Open Container Initiative, <https://github.com/opencontainers/image-spec/blob/v1.1.0/spec.md>.
- **[OCI-DIST]** *OCI Distribution Specification*, version 1.1.0, Open Container Initiative, <https://github.com/opencontainers/distribution-spec/blob/v1.1.0/spec.md>.
