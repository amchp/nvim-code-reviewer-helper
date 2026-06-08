# Glossary

## Codebase Review

A Review Session that summarizes repository structure and orders real repository files for a first-pass codebase walkthrough. It ignores dirty git status when selecting the review mode.

## Git Changes Review

A Review Session that reviews one aggregate diff from `HEAD~N` to the current working tree, including selected commits, uncommitted tracked changes, and configured untracked files.

## Review Overview

The virtual first item in every Review Session. It is rendered in a scratch buffer and does not correspond to a real repository file.

## Review Session

The persisted review workspace created by Codebase Review or Git Changes Review, including the overview, ordered items, current position, and reopenable UI state.
