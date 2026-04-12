# Architecture

## Overview

This Crystal port of Rust's `regex-automata` crate provides finite automata implementations for regular expression matching. The architecture follows the upstream Rust implementation closely to ensure behavior parity.

## Components

### Core Modules

1. **HIR Compiler** (`src/hir_compiler.cr`): Compiles regex-syntax HIR into Thompson NFA
2. **NFA** (`src/nfa.cr`): Thompson NFA implementation
3. **DFA** (`src/dfa/`): Deterministic Finite Automata with subset construction
4. **Hybrid Engine** (`src/hybrid/`): Lazy DFA with on-demand state expansion

### Data Flow

1. Regex pattern → regex-syntax HIR
2. HIR → Thompson NFA (via `HirCompiler`)
3. NFA → DFA (via subset construction)
4. DFA/Hybrid → Pattern matching

## Design Principles

- **Behavior parity**: Exact match with Rust upstream semantics
- **Performance**: Linear time `O(m * n)` worst-case guarantees
- **Memory efficiency**: Sparse and dense DFA representations
- **No-std compatibility**: Designed for embedded/constrained environments

## Key Data Structures

- `NFA`: Thompson NFA with state transitions
- `DFA::Builder`: Constructs DFA from NFA
- `Hybrid::LazyDFA`: On-demand state expansion
- `PatternID`: Unique identifier for regex patterns