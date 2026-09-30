# CSIL: Folder Backend Profile

| Version   | 1.0.0      |
| --------- | ---------- |
| Published | 2026-09-30 |

## Contents

- [Scope](#scope)
- [Requirements language](#requirements-language)
- [Terminology](#terminology)
- [1. Metadata carrier](#1-metadata-carrier)
  - [1.1 Reference resolution](#11-reference-resolution)
  - [1.2 Platform descriptor encoding](#12-platform-descriptor-encoding)
  - [1.3 Value encoding](#13-value-encoding)
- [2. Runtime layer](#2-runtime-layer)
- [3. Application layer](#3-application-layer)
- [4. Execution layer](#4-execution-layer)
- [5. Native execution](#5-native-execution)
  - [5.1 Working directory](#51-working-directory)
  - [5.2 Tool catalog](#52-tool-catalog)
  - [5.3 Data directories](#53-data-directories)
- [Normative references](#normative-references)

## Scope

This document defines the folder backend profile for the CSIL Node Packaging Specification [CSIL].
It specifies how the vocabulary defined in that specification is carried by a directory tree on a local or shared file system (the folder registry), and how the nodes it serves are executed natively as host processes (local execution).

The folder backend targets tools that are installed directly on a host and run in place, without containerization.
It is the native counterpart of the OCI backend.
Producers SHOULD use the OCI backend when bit-exact reproducibility matters.

## Requirements language

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in BCP 14 [RFC2119] [RFC8174] when, and only when, they appear in all capitals, as shown here.

## Terminology

The roles defined in [CSIL] *Terminology* apply unchanged.

## 1. Metadata carrier

The folder registry is a directory rooted at a configured path.
It stores nodes as sub-folders and carries the [CSIL] §6 metadata vocabulary as plain UTF-8 YAML key/value maps.
The `csil.*` key vocabulary is used unchanged as the map keys.

The carrier used is a metadata map located at `<root>/<name>/<version>/_meta.yaml` and exists for runtime [CSIL] §6.2, application [CSIL] §6.3 and execution [CSIL] §6.4 layers.

The registry directory layout is:

```txt
<root>/
  <name>/
    <version>/
      _meta.yaml                 # metadata map ([CSIL] §6)
      <content files...>         # scripts, binaries, configuration
```

The following rules apply:

- A `<name>` sub-folder is a repository.
  It MAY hold several `<version>` sub-folders side by side.
  Resolution of a reference that omits the version is defined in §1.1.
- `<name>` is the full repository component of a reference (the reference with any registry host and tag removed, dots included), so a reference addressed to a folder regsitry resolves to the identically named sub-folder.
- Names beginning with `_` are reserved for registry use (e.g., `_meta.yaml`).
- Within a version folder, `_meta.yaml` and the content files are laid out flat.
  `_meta.yaml` is metadata, not runnable content, and orchestration MUST NOT materialize it as CSIL layer content.
- A version folder that contains no `_meta.yaml` is not a CSIL layer.
  Tooling MUST ignore it rather than reject the registry, so that a registry may hold unrelated content alongside CSIL layers.

### 1.1 Reference resolution

A reference under this profile takes the form `<registry>/<repository>[:<tag>]`.

`<repository>` names the `<root>/<name>` sub-folder; `<tag>` names the `<version>` sub-folder beneath it.

When a reference **omits** the tag, tooling MUST select the highest version present, ordered as follows:

1. Split each version folder name into a sequence of numeric and non-numeric runs.
2. Compare the sequences element by element.
   Two numeric runs compare as integers, so `10` is greater than `9` and leading zeros are insignificant.
   Two non-numeric runs compare as byte strings.
   A numeric run sorts before a non-numeric run.
3. If one sequence is a prefix of the other, the shorter sorts first.

This is a natural-order comparison, not a lexical one.
Lexical ordering would place `1.9.0` above `1.10.0` and MUST NOT be used, because two consumers resolving the same untagged reference need to select the same node.

This ordering is a resolution convenience only.
It imposes no versioning scheme on producers, and [CSIL] defines no ordering over `application.version` ([CSIL] §6.3).
A reference whose resolution must be stable SHOULD name its tag explicitly.

### 1.2 Platform descriptor encoding

The platform descriptor ([CSIL] §6.8) is carried by the `csil.*` metadata vocabulary as ordinary map keys.

### 1.3 Value encoding

A value is carried as a JSON string and read back byte for byte.
No type coercion is possible or permitted.

A producer MUST NOT encode a value as a JSON number, boolean, null, array or object.
A boolean is the JSON string `"true"` or `"false"`, never the JSON literal `true` or `false`.
An integer is a JSON string of digits, never a JSON number.
A consumer encountering a non-string JSON value under a `csil.` key MUST reject the layer.

An empty value is the empty JSON string `""`.
It denotes a present key with an empty value, which [CSIL] §6.1.4 distinguishes from an absent key.
A producer MUST NOT express "absent" by emitting an empty string, and a consumer MUST NOT treat an empty string as absence.

## 2. Runtime layer

A runtime layer is a versioned CSIL layer whose `_meta.yaml` sets `csil.type` to `runtime`.
Its content files (scripts, binaries) MUST be stored flat in the version folder.

The tool binaries themselves MAY be installed natively on the host and packaging is optional.

The runtime prologue ([CSIL] §3.2) is a host concern configured in the tool catalog (§5.2).

## 3. Application layer

A folder application layer is a versioned CSIL layer whose `_meta.yaml` sets `csil.type` to `application`.
Its content files (compiled model binaries, configuration files) MUST be stored flat in the version folder.

## 4. Execution layer

A folder execution layer is a distinct CSIL layer whose `_meta.yaml` sets `csil.type` to `execute`.
Its content files (scripts, compiled model binaries, configuration files) MUST be stored flat in the version folder.

## 5. Native execution

Orchestration executes nodes served by a folder registry as native host processes.
This section defines the execution model.

### 5.1 Working directory

The node content MUST be materialized flat into a working directory that becomes the launched process's working directory and MUST persist after the tool process exits.
The working directory MUST be a uniquely named temporary directory, created per launch and outside the registry, so a registry stays free of execution state and concurrent launches of the same node never share a working directory.
The working directory's path MUST be recorded in the node's state, to allow the orchestrating tool to later remove that specific directory.

### 5.2 Tool catalog

Because runtime tools are installed on the host and not packaged, orchestration resolves a runtime reference (`csil.execute.runtime`, or `csil.application.runtime-id` for an application node) to a local installation via a host-side tool catalog.

#### 5.2.1 Prologue

The host-side tool catalog carries the host-specific information about the runtime prologue [CSIL] §3.2.
It is not part of the registry, as it can not travel between hosts.

A native runtime reference is a mutable tag over a host installation, not a content digest: the bits behind an install path can change under it (a patch or reinstall).

### 5.3 Data directories

A node's declared data directories ([CSIL] §6.9) require no storage beyond the working directory of §5.1, which already outlives the launched process.
The working directory satisfies [CSIL] §6.9.1 on its own, so tooling provisions nothing further.

A data directory MUST be declared **relative to the node's own content**, which is also the launched process's working directory (§5.1).
Tooling MUST reject an absolute data directory rather than resolve it.

## Normative references

- **[RFC2119]** Bradner, S., "Key words for use in RFCs to Indicate Requirement Levels", BCP 14, RFC 2119, DOI 10.17487/RFC2119, March 1997, <https://www.rfc-editor.org/info/rfc2119>.
- **[RFC8174]** Leiba, B., "Ambiguity of Uppercase vs Lowercase in RFC 2119 Key Words", BCP 14, RFC 8174, DOI 10.17487/RFC8174, May 2017, <https://www.rfc-editor.org/info/rfc8174>.
- **[CSIL]** *CSIL Node Packaging Specification*, version 1.0.0 ([SPEC](SPEC.md)).
- **[CSIL-OCI]** *CSIL Node Packaging Specification: OCI Backend Profile*, version 1.0.0 ([OCI](OCI.md)).
